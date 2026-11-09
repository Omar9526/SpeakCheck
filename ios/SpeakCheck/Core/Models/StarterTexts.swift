import Foundation

/// Готовые тексты, чтобы получить первую оценку за минуту без загрузки файла (условие совета, founder/board.md).
/// Реальный учебный контент (не mock): образцы ответов IELTS Speaking и собеседования, которые
/// пользователь читает вслух и получает настоящую оценку. Каждый абзац ≤ 40 слов — один фрагмент,
/// чтобы Azure оценивал и пропуски слов (miscue работает только на записях до 30 секунд).
struct StarterText: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    /// Для какой цели текст; nil — подходит всем (звуковые челленджи).
    let goal: PracticeGoal.Kind?
    let paragraphs: [String]
}

enum StarterTexts {
    static let all: [StarterText] = [
        StarterText(
            id: "ielts-p1-hometown",
            title: "IELTS Part 1: родной город",
            subtitle: "Короткие ответы · 3 фрагмента",
            icon: "graduationcap.fill",
            goal: .ielts,
            paragraphs: [
                "I come from a city surrounded by mountains. In summer, people usually go hiking, and in winter, the slopes are full of skiers.",
                "What I appreciate most about my hometown is the atmosphere. People are hospitable, the food is delicious, and there is always something to celebrate.",
                "If I could change one thing, I would improve public transport, because the traffic in the city centre can be really frustrating during rush hour."
            ]
        ),
        StarterText(
            id: "ielts-p1-work",
            title: "IELTS Part 1: работа и учёба",
            subtitle: "Короткие ответы · 3 фрагмента",
            icon: "graduationcap.fill",
            goal: .ielts,
            paragraphs: [
                "At the moment I work as a software developer at a local company. My main responsibility is building features for our mobile app.",
                "What I enjoy most is solving problems with my team. Every week brings a new challenge, so the job never feels boring.",
                "In the future, I would like to study abroad and get a master's degree, which is one of the reasons I am taking this exam."
            ]
        ),
        StarterText(
            id: "ielts-p2-skill",
            title: "IELTS Part 2: навык, который вы освоили",
            subtitle: "Монолог · 4 фрагмента",
            icon: "text.bubble.fill",
            goal: .ielts,
            paragraphs: [
                "I would like to talk about a skill I learned a couple of years ago, which is cooking. Before that, I could hardly make a simple breakfast.",
                "I started learning during the winter holidays. I watched short videos online and practised every evening, beginning with soups and simple salads.",
                "The most difficult part was timing. At first, I burned almost everything, but slowly I learned to prepare several dishes at the same time.",
                "Now I really enjoy cooking for my friends and family. It taught me that patience and regular practice matter much more than talent."
            ]
        ),
        StarterText(
            id: "ielts-p3-technology",
            title: "IELTS Part 3: технологии и образование",
            subtitle: "Рассуждение · 3 фрагмента",
            icon: "text.bubble.fill",
            goal: .ielts,
            paragraphs: [
                "In my opinion, technology has changed education dramatically. Students can now access lectures from the world's best universities without leaving home.",
                "However, I believe there are some drawbacks as well. Many young people find it difficult to concentrate because their phones constantly distract them.",
                "On balance, I would say technology is a powerful tool, but only when teachers show students how to use it wisely and responsibly."
            ]
        ),
        StarterText(
            id: "interview-about-me",
            title: "Собеседование: расскажите о себе",
            subtitle: "Самопрезентация · 3 фрагмента",
            icon: "briefcase.fill",
            goal: .interview,
            paragraphs: [
                "Thank you for inviting me. I have three years of experience in customer support, and I really enjoy solving problems for people.",
                "In my previous role, I handled around forty requests a day and helped our team reduce the average response time by almost half.",
                "Now I am looking for a company where I can grow professionally, learn new skills, and contribute to an ambitious international team."
            ]
        ),
        StarterText(
            id: "interview-strengths",
            title: "Собеседование: сильные и слабые стороны",
            subtitle: "Частые вопросы · 3 фрагмента",
            icon: "briefcase.fill",
            goal: .interview,
            paragraphs: [
                "My greatest strength is that I stay calm under pressure. When a deadline is close, I break the work into small steps and focus on priorities.",
                "As for weaknesses, I sometimes spend too long polishing details. I have learned to agree on clear deadlines with my team so this does not slow us down.",
                "You should hire me because I learn quickly, communicate clearly, and genuinely care about the results of my work and the people I work with."
            ]
        ),
        StarterText(
            id: "th-challenge",
            title: "Челлендж: звук TH",
            subtitle: "Скороговорки · 3 строки",
            icon: "flame.fill",
            goal: nil,
            paragraphs: [
                "The thirty-three thieves thought that they thrilled the throne throughout Thursday.",
                "I thought a thought, but the thought I thought was not the thought I thought I thought.",
                "Three thin thinkers thinking thick thoughts through the thunder."
            ]
        )
    ]

    /// Сначала тексты под цель пользователя, затем остальные.
    static func ordered(for goal: PracticeGoal.Kind?) -> [StarterText] {
        guard let goal, goal != .general else { return all }
        return all.filter { $0.goal == goal } + all.filter { $0.goal != goal }
    }

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
