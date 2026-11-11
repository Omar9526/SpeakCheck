import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var editingGoal: PracticeGoal?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header

                // Первая оценка — за минуту: готовые тексты выше цели и загрузки (условие совета).
                if store.attempts.isEmpty {
                    starterSection
                }

                GoalCard(goal: store.goal, attempts: store.attempts,
                         onEdit: { kind in
                             editingGoal = store.goal.map { var g = $0; g.kind = kind ?? $0.kind; return g }
                                 ?? PracticeGoal(kind: kind ?? .ielts, date: nil)
                         },
                         onPractice: { router.tab = .tasks })

                if let doc = store.continueDocument {
                    continueCard(doc)
                }

                if !store.attempts.isEmpty {
                    starterSection
                }

                Button {
                    router.push(.importDocument)
                } label: {
                    Label("Свой текст: PDF, Word, фото", systemImage: "arrow.up.doc.fill")
                }
                .buttonStyle(.secondary)

                recentSection
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editingGoal) { goal in
            GoalSetupSheet(goal: goal) { store.goal = $0 }
        }
    }



    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            BrandMark()
                .padding(.top, Theme.Spacing.s)
            Text(headline)
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Читайте вслух — увидите, какие звуки вас выдают, и почему.")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var headline: String {
        switch store.goal?.kind {
        case .ielts: "Подготовка к IELTS Speaking"
        case .interview: "Подготовка к собеседованию на английском"
        default: "Говорите по-английски чисто и уверенно"
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
            SectionHeader(title: store.attempts.isEmpty ? "Начните с готового ответа" : "Готовые ответы")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.m) {
                    ForEach(StarterTexts.ordered(for: store.goal?.kind)) { starter in
                        Button {
                            let doc = store.starterDocument(starter)
                            router.push(.document(doc.id))
                        } label: {
                            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                                IconTile(systemName: starter.icon, tint: starter.goal == nil ? Theme.Colors.warning : Theme.Colors.accentLight)
                                Spacer(minLength: 0)
                                Text(starter.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(3)
                                Text(starter.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            .frame(width: 160, height: 150, alignment: .leading)
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
