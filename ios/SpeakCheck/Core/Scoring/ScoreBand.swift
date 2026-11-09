import SwiftUI

/// Цветовая полоса оценки. Пороги — UX-эвристика, не стандарт CEFR (ТЗ, раздел 6),
/// поэтому вынесены в конфигурацию.
struct ScoreThresholds: Sendable, Equatable {
    var good: Double = 85
    var fair: Double = 65

    static let `default` = ScoreThresholds()
}

enum ScoreBand: Sendable, Equatable {
    case good, fair, poor

    init(score: Double, thresholds: ScoreThresholds = .default) {
        if score >= thresholds.good {
            self = .good
        } else if score >= thresholds.fair {
            self = .fair
        } else {
            self = .poor
        }
    }

    var color: Color {
        switch self {
        case .good: Theme.Colors.success
        case .fair: Theme.Colors.warning
        case .poor: Theme.Colors.danger
        }
    }

    var title: String {
        switch self {
        case .good: "Правильно"
        case .fair: "Требует улучшения"
        case .poor: "Ошибка"
        }
    }

    /// Короткая словесная оценка под кольцом.
    var verdict: String {
        switch self {
        case .good: "Хорошо"
        case .fair: "Неплохо"
        case .poor: "Нужна практика"
        }
    }
}
