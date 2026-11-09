import SwiftUI

/// Документ: список фрагментов, прогресс, начало чтения.
struct DocumentView: View {
    let documentID: UUID

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let doc = store.document(id: documentID) {
                content(doc)
            } else {
                EmptyStateView(icon: "doc.questionmark", title: "Документ удалён", message: "Вернитесь на главный экран.")
                    .padding()
            }
        }
        .screenBackground()
        .navigationTitle("Документ")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ doc: SCDocument) -> some View {
        let attempts = store.attempts(for: doc.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(doc.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    HStack {
                        Chip(text: doc.source.badge)
                        Chip(text: "English", tint: Theme.Colors.accentLight)
                        Chip(text: "\(doc.segments.count) фрагм.")
                    }
                    ThinProgress(value: doc.progress)
                        .padding(.top, Theme.Spacing.s)
                }

                Button {
                    router.push(.reader(documentID: doc.id, segmentIndex: min(doc.completedSegments, max(doc.segments.count - 1, 0))))
                } label: {
                    Label(doc.completedSegments == 0 ? "Начать чтение" : "Продолжить чтение", systemImage: "mic.fill")
                }
                .buttonStyle(.primary)
                .disabled(doc.segments.isEmpty)

                SectionHeader(title: "Фрагменты", action: ("Изменить", { router.push(.textReview(documentID: doc.id)) }))

                ForEach(Array(doc.segments.enumerated()), id: \.element.id) { index, segment in
                    Button {
                        router.push(.reader(documentID: doc.id, segmentIndex: index))
                    } label: {
                        segmentRow(index: index, segment: segment, attempts: attempts.filter { $0.segmentID == segment.id })
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Исправить текст", systemImage: "pencil") { router.push(.textReview(documentID: doc.id)) }
                    Button("Удалить документ", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Удалить документ и все попытки?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                store.deleteDocument(id: doc.id)
                dismiss()
            }
        }
    }

    private func segmentRow(index: Int, segment: ReadingSegment, attempts: [ReadingAttempt]) -> some View {
        let best = attempts.compactMap { $0.assessment?.overall }.max()
        return HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Text("\(index + 1)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.Colors.accentLight)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.Colors.accent.opacity(0.15)))
            VStack(alignment: .leading, spacing: 6) {
                Text(segment.referenceText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text(attempts.isEmpty ? "Не прочитано" : "Попыток: \(attempts.count)")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
            if let best {
                Text("\(Int(best.rounded()))%")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(ScoreBand(score: best).color)
            }
        }
        .card(padding: Theme.Spacing.m, radius: Theme.Radius.medium)
    }
}

#if DEBUG
#Preview {
    let store = AppStore.demo()
    return NavigationStack { DocumentView(documentID: store.documents[0].id) }
        .environment(store)
        .environment(Router())
}
#endif
