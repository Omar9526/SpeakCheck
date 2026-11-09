import Foundation

/// Цель подготовки — главная причина возвращаться (решение совета, founder/board.md):
/// человек готовится к конкретной дате, приложение показывает обратный отсчёт и план на сегодня.
struct PracticeGoal: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(kind.rawValue)-\(date?.timeIntervalSince1970 ?? 0)-\(dailyTarget)" }
    enum Kind: String, Codable, CaseIterable, Sendable {
        case ielts, interview, general

        var title: String {
            switch self {
            case .ielts: "IELTS Speaking"
            case .interview: "Собеседование"
            case .general: "Уверенная речь"
            }
        }

        var icon: String {
            switch self {
            case .ielts: "graduationcap.fill"
            case .interview: "briefcase.fill"
            case .general: "waveform"
            }
        }

        /// «До экзамена 12 дней» / «До собеседования 3 дня».
        var eventName: String {
            switch self {
            case .ielts: "экзамена"
            case .interview: "собеседования"
            case .general: "цели"
            }
        }
    }

    var kind: Kind
    var date: Date?
    /// Сколько фрагментов прочитать за день.
    var dailyTarget: Int = 3

    /// Полных дней до даты (0 — сегодня), nil — дата не задана или прошла.
    func daysLeft(now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let date else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return days >= 0 ? days : nil
    }

    /// Сколько фрагментов с оценкой прочитано сегодня.
    static func doneToday(attempts: [ReadingAttempt], now: Date = .now, calendar: Calendar = .current) -> Int {
        attempts.filter { $0.status == .completed && calendar.isDate($0.createdAt, inSameDayAs: now) }.count
    }
}
