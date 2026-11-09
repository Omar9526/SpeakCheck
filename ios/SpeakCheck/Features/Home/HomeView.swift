import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header

                if !store.attempts.isEmpty {
                    StreakBadge(streak: Engagement.streak(attempts: store.attempts),
                                practicedToday: Engagement.practicedToday(attempts: store.attempts))
                }

                if let doc = store.continueDocument {
                    continueCard(doc)
                }

                Button {
                    router.push(.importDocument)
                } label: {
                    Label("Загрузить документ", systemImage: "arrow.up.doc.fill")
                }
                .buttonStyle(.primary)

                starterSection

                WordOfDayCard(word: Engagement.wordOfTheDay()) {
                    practice(Engagement.wordOfTheDay().example, title: "Слово дня: \(Engagement.wordOfTheDay().word)")
                }

                let difficult = Engagement.difficultWords(attempts: store.attempts)
                if !difficult.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        SectionHeader(title: "Мои трудные слова")
                        DifficultWordsCard(words: difficult) { word in
                            practice(word, title: "Тренировка: \(word)")
                        }
                    }
                }

                recentSection
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Мини-тренировка: документ из одного слова/фразы, сразу на экран чтения.
    private func practice(_ text: String, title: String) {
        let doc = SCDocument(
            id: UUID(), title: title, source: .manual, status: .ready,
            segments: [ReadingSegment(id: UUID(), sequence: 0, referenceText: text, pageNumber: nil)],
            createdAt: .now, bestScore: nil, completedSegments: 0
        )
        store.add(doc)
        router.push(.reader(documentID: doc.id, segmentIndex: 0))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            BrandMark()
                .padding(.top, Theme.Spacing.s)
            Text("Ваш тренер по английскому произношению")
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Читайте свой текст вслух и получайте оценку по каждому слову.")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func continueCard(_ doc: SCDocument) -> some View {
        Button {
            router.push(.reader(documentID: doc.id, segmentIndex: min(doc.completedSegments, doc.segments.count - 1)))
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    Chip(text: "Продолжить чтение", tint: Theme.Colors.accentLight)
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                        .foregroundStyle(Theme.Colors.accentGradient)
                }
                Text(doc.title)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                ThinProgress(value: doc.progress)
                Text("\(doc.completedSegments) из \(doc.segments.count) фрагментов")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private var starterSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Попробуйте сразу")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.m) {
                    ForEach(StarterTexts.all) { starter in
                        Button {
                            let doc = store.add(StarterTexts.document(from: starter))
                            router.push(.document(doc.id))
                        } label: {
                            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                                IconTile(systemName: starter.icon, tint: starter.id.contains("challenge") ? Theme.Colors.warning : Theme.Colors.accentLight)
                                Spacer(minLength: 0)
                                Text(starter.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                Text(starter.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            .frame(width: 150, height: 136, alignment: .leading)
                            .card(padding: Theme.Spacing.m, radius: Theme.Radius.medium)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Мои документы")
            if store.documents.isEmpty {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "Пока пусто",
                    message: "Загрузите PDF, Word, TXT или фото текста — или начните с готового текста выше."
                )
            } else {
                ForEach(store.documents.prefix(5)) { doc in
                    Button { router.push(.document(doc.id)) } label: {
                        DocumentRow(document: doc)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct DocumentRow: View {
    var document: SCDocument

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            IconTile(systemName: icon)
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(document.source.badge)
                    Text("·")
                    Text("\(document.completedSegments)/\(document.segments.count) фрагм.")
                }
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
            if let score = document.bestScore {
                Text("\(Int(score.rounded()))%")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(ScoreBand(score: score).color)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .card(padding: Theme.Spacing.m, radius: Theme.Radius.medium)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch document.source {
        case .pdf: "doc.richtext.fill"
        case .docx: "doc.text.fill"
        case .txt: "doc.plaintext.fill"
        case .image: "photo.fill"
        case .manual: "text.book.closed.fill"
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { HomeView().routeDestinations() }
        .environment(AppStore.demo())
        .environment(Router())
}
#endif
