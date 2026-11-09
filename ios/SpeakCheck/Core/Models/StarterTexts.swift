import Foundation

/// Готовые тексты, чтобы попробовать приложение за 10 секунд без загрузки файла.
/// Это реальный учебный контент (не mock): пользователь читает его и получает настоящую оценку.
struct StarterText: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let paragraphs: [String]
}

enum StarterTexts {
    static let all: [StarterText] = [
        StarterText(
            id: "why-english",
            title: "Зачем учить английский",
            subtitle: "Лёгкий · 3 абзаца",
            icon: "globe.europe.africa.fill",
            paragraphs: [
                "Learning English is important because it helps us communicate with people around the world, find better job opportunities, and access more information.",
                "Many books, films, and online courses are created in English first. When you understand the language, you can enjoy them without waiting for a translation.",
                "The best way to improve is to practice a little every day. Read out loud, listen carefully, and do not be afraid of making mistakes."
            ]
        ),
        StarterText(
            id: "job-interview",
            title: "Собеседование",
            subtitle: "Средний · 3 абзаца",
            icon: "briefcase.fill",
            paragraphs: [
                "Thank you for inviting me to this interview. I have three years of experience in customer support, and I enjoy solving problems for people.",
                "In my previous role, I handled around forty requests a day and helped our team reduce the average response time by almost half.",
                "I am looking for a company where I can grow professionally, learn new skills, and contribute to a friendly and ambitious team."
            ]
        ),
        StarterText(
            id: "ielts-speaking",
            title: "IELTS Speaking: родной город",
            subtitle: "Средний · 2 абзаца",
            icon: "graduationcap.fill",
            paragraphs: [
                "I come from a city surrounded by beautiful mountains. In the summer, people usually go hiking, and in the winter, the slopes are full of skiers.",
                "What I appreciate most about my hometown is the atmosphere. People are hospitable, the food is delicious, and there is always something to celebrate."
            ]
        ),
        StarterText(
            id: "th-challenge",
            title: "Челлендж: звук TH",
            subtitle: "Скороговорки · 3 строки",
            icon: "flame.fill",
            paragraphs: [
                "The thirty-three thieves thought that they thrilled the throne throughout Thursday.",
                "I thought a thought, but the thought I thought was not the thought I thought I thought.",
                "Three thin thinkers thinking thick thoughts through the thunder."
            ]
        ),
        StarterText(
            id: "rw-challenge",
            title: "Челлендж: R и W",
            subtitle: "Скороговорки · 3 строки",
            icon: "bolt.fill",
            paragraphs: [
                "Red lorry, yellow lorry, red lorry, yellow lorry.",
                "Which wristwatches are Swiss wristwatches?",
                "Rory the warrior and Roger the worrier were reared wrongly in a rural brewery."
            ]
        )
    ]

    static func document(from starter: StarterText) -> SCDocument {
        SCDocument(
            id: UUID(),
            title: starter.title,
            source: .manual,
            status: .ready,
            segments: starter.paragraphs.enumerated().map { index, text in
                ReadingSegment(id: UUID(), sequence: index, referenceText: text, pageNumber: nil)
            },
            createdAt: .now,
            bestScore: nil,
            completedSegments: 0
        )
    }
}
