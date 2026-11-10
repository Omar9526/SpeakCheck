import AVFoundation
import CryptoKit
import Observation

/// Эталонное произношение. Основной путь — живой нейросетевой голос Azure через наш сервер
/// (MP3 кэшируется и на сервере, и на устройстве). Без сервера или при ошибке —
/// лучший системный голос iPhone, чтобы кнопка «Послушать» работала всегда.
@MainActor
@Observable
final class SpeechPlayer: NSObject {
    private(set) var isSpeaking = false
    private(set) var isLoading = false
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var loadTask: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, slow: Bool = false) {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        isSpeaking = true

        guard APIClient.baseURL != nil else { return speakLocally(text, slow: slow) }
        isLoading = true
        loadTask = Task {
            let data = await Self.neuralAudio(text, slow: slow)
            guard !Task.isCancelled else { return }
            isLoading = false
            if let data, let player = try? AVAudioPlayer(data: data) {
                self.player = player
                player.delegate = self
                player.play()
            } else {
                speakLocally(text, slow: slow)
            }
        }
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        player?.stop()
        player = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isLoading = false
        isSpeaking = false
    }

    // MARK: Живой голос (сервер → Azure)

    private struct Body: Encodable, Sendable { let text: String; let slow: Bool }

    private static func neuralAudio(_ text: String, slow: Bool) async -> Data? {
        let file = cacheURL(text: text, slow: slow)
        if let cached = try? Data(contentsOf: file) { return cached }
        guard let data = try? await APIClient.shared.postForData("speech", json: Body(text: text, slow: slow)),
              !data.isEmpty else { return nil }
        try? data.write(to: file, options: .atomic)
        return data
    }

    private static func cacheURL(text: String, slow: Bool) -> URL {
        let digest = SHA256.hash(data: Data("\(slow ? 1 : 0)|\(text)".utf8)).map { String(format: "%02x", $0) }.joined()
        let folder = URL.cachesDirectory.appending(path: "speech", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "\(digest).mp3")
    }

    // MARK: Запасной путь — системный голос

    private func speakLocally(_ text: String, slow: Bool) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice()
        utterance.rate = slow ? AVSpeechUtteranceDefaultSpeechRate * 0.7 : AVSpeechUtteranceDefaultSpeechRate * 0.92
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Лучший установленный en-US голос: Premium → Enhanced → обычный.
    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        return voices.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}

extension SpeechPlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

extension SpeechPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isSpeaking = false
            self.player = nil
        }
    }
}
