import AVFoundation
import Observation

/// Запись голоса для оценки: AVAudioEngine → конвертация в WAV PCM 16 кГц / 16 бит / mono
/// (формат, который Azure Pronunciation Assessment принимает без перекодирования).
@MainActor
@Observable
final class AudioRecorder {
    enum State: Equatable {
        case idle, recording, paused, stopped
    }

    enum RecorderError: Error, Equatable {
        case permissionDenied
        case engineFailed
        case tooQuiet
        case tooShort
    }

    static let maxDuration: TimeInterval = 90
    static let minDuration: TimeInterval = 1.0
    static let levelHistory = 48

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var levels: [Float] = Array(repeating: 0.04, count: AudioRecorder.levelHistory)
    private(set) var fileURL: URL?

    private let engine = AVAudioEngine()
    private var sink: RecordingSink?
    private var timer: Timer?
    private var segmentStart: Date?
    private var accumulated: TimeInterval = 0

    var onAutoStop: (() -> Void)?

    // MARK: Permission

    static var permission: AVAudioApplication.recordPermission {
        AVAudioApplication.shared.recordPermission
    }

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    // MARK: Control

    func start() async throws {
        guard await Self.requestPermission() else { throw RecorderError.permissionDenied }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let url = Self.draftsDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw RecorderError.engineFailed }

        let sink = try RecordingSink(url: url, inputFormat: inputFormat) { [weak self] level in
            Task { @MainActor in self?.push(level: level) }
        }
        RecordingSink.install(sink, on: input, format: inputFormat)
        self.sink = sink
        fileURL = url

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw RecorderError.engineFailed
        }

        accumulated = 0
        elapsed = 0
        segmentStart = .now
        state = .recording
        startTimer()
    }

    func pause() {
        guard state == .recording else { return }
        engine.pause()
        accumulated += Date.now.timeIntervalSince(segmentStart ?? .now)
        segmentStart = nil
        state = .paused
        timer?.invalidate()
    }

    func resume() throws {
        guard state == .paused else { return }
        try engine.start()
        segmentStart = .now
        state = .recording
        startTimer()
    }

    /// Останавливает запись и возвращает готовый файл. Проверяет длительность и громкость.
    func stop() throws -> (url: URL, durationMs: Int) {
        if state == .recording { accumulated += Date.now.timeIntervalSince(segmentStart ?? .now) }
        timer?.invalidate()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        state = .stopped
        elapsed = accumulated

        let peak = sink?.finish() ?? 0
        sink = nil
        guard let url = fileURL else { throw RecorderError.engineFailed }
        guard accumulated >= Self.minDuration else {
            try? FileManager.default.removeItem(at: url)
            throw RecorderError.tooShort
        }
        // Слишком тихая запись не даст надёжной оценки (ТЗ 4.3).
        guard peak > 0.02 else {
            try? FileManager.default.removeItem(at: url)
            throw RecorderError.tooQuiet
        }
        return (url, Int(accumulated * 1000))
    }

    /// Сброс без сохранения (кнопка «Заново» / уход с экрана).
    func discard() {
        timer?.invalidate()
        if state == .recording || state == .paused {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            _ = sink?.finish()
        }
        sink = nil
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        fileURL = nil
        state = .idle
        elapsed = 0
        accumulated = 0
        levels = Array(repeating: 0.04, count: Self.levelHistory)
    }

    /// Сбрасывает экран к исходному состоянию, НЕ удаляя файл (он передан в обработку как черновик).
    func discardStateOnly() {
        fileURL = nil
        state = .idle
        elapsed = 0
        accumulated = 0
        levels = Array(repeating: 0.04, count: Self.levelHistory)
    }

    // MARK: Internals

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard state == .recording else { return }
        elapsed = accumulated + Date.now.timeIntervalSince(segmentStart ?? .now)
        if elapsed >= Self.maxDuration {
            pause()
            onAutoStop?()
        }
    }

    private func push(level: Float) {
        guard state == .recording else { return }
        levels.removeFirst()
        levels.append(max(0.04, min(1, level)))
    }

    nonisolated static var draftsDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpeakCheck/Drafts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// Работает на аудиопотоке: конвертирует буферы и пишет файл. Не изолирован от MainActor намеренно.
final class RecordingSink: @unchecked Sendable {
    static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

    private let lock = NSLock()
    private var file: AVAudioFile?
    private let converter: AVAudioConverter
    private let onLevel: @Sendable (Float) -> Void
    private var peak: Float = 0

    init(url: URL, inputFormat: AVAudioFormat, onLevel: @escaping @Sendable (Float) -> Void) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: Self.targetFormat) else {
            throw AudioRecorder.RecorderError.engineFailed
        }
        self.converter = converter
        self.onLevel = onLevel
        file = try AVAudioFile(forWriting: url, settings: Self.targetFormat.settings,
                               commonFormat: .pcmFormatInt16, interleaved: true)
    }

    /// Ставит tap. `nonisolated static`, чтобы замыкание не унаследовало MainActor
    /// (оно вызывается на аудиопотоке).
    nonisolated static func install(_ sink: RecordingSink, on node: AVAudioInputNode, format: AVAudioFormat) {
        node.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            sink.process(buffer)
        }
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        let level = Self.rms(buffer)
        onLevel(min(1, level * 6))

        let ratio = Self.targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0 else { return }

        lock.lock()
        peak = max(peak, level)
        try? file?.write(from: out)
        lock.unlock()
    }

    /// Закрывает файл; возвращает пиковый RMS для проверки «слишком тихо».
    func finish() -> Float {
        lock.lock()
        defer { lock.unlock() }
        file = nil
        return peak
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        return (sum / Float(n)).squareRoot()
    }
}
