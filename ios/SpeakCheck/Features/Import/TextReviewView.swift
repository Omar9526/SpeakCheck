import SwiftUI

/// Проверка и исправление извлечённого текста перед чтением (ТЗ 4.1, 6: ошибки OCR исправляет пользователь).
struct TextReviewView: View {
    let documentID: UUID

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var title = ""
    @State private var segments: [ReadingSegment] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                hint

                VStack(alignment: .leading, spacing: 6) {
                    Text("Название")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    TextField("Название", text: $title)
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(Theme.Spacing.m)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.small).fill(Theme.Colors.surface))
                }

                HStack {
                    Chip(text: "Язык: English", tint: Theme.Colors.accentLight)
                    Chip(text: "\(segments.count) фрагм.")
                    Chip(text: "\(segments.reduce(0) { $0 + $1.wordCount }) слов")
                }

                ForEach($segments) { $segment in
                    segmentEditor($segment)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button {
                save()
                router.popToRoot()
                router.push(.document(documentID))
            } label: {
                Label("Сохранить и читать", systemImage: "checkmark")
            }
            .buttonStyle(.primary)
            .disabled(cleanedSegments.isEmpty)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
            .background(Theme.Colors.background.opacity(0.95))
        }
        .screenBackground()
        .navigationTitle("Проверка текста")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private var hint: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.Colors.accentLight)
            Text("Проверьте текст: оценка сравнивает вашу речь именно с ним. Исправьте ошибки распознавания и удалите лишнее (номера страниц, заголовки).")
                .font(.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .card(padding: Theme.Spacing.m, radius: Theme.Radius.medium)
    }

    private func segmentEditor(_ segment: Binding<ReadingSegment>) -> some View {
        let index = segments.firstIndex { $0.id == segment.wrappedValue.id } ?? 0
        let words = segment.wrappedValue.wordCount
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text("Фрагмент \(index + 1)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let page = segment.wrappedValue.pageNumber {
                    Text("· стр. \(page)")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Text("\(words) слов")
                    .font(.caption)
                    .foregroundStyle(words > TextSegmenter.maxWordsPerSegment ? Theme.Colors.warning : Theme.Colors.textSecondary)
                Button(role: .destructive) {
                    segments.removeAll { $0.id == segment.wrappedValue.id }
                } label: {
                    Image(systemName: "trash")
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.danger)
                }
                .accessibilityLabel("Удалить фрагмент \(index + 1)")
            }
            TextEditor(text: segment.referenceText)
                .scrollContentBackground(.hidden)
                .font(.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(minHeight: 90)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: Theme.Spacing.m, radius: Theme.Radius.medium)
    }

    private var cleanedSegments: [ReadingSegment] {
        segments
            .map { seg in
                var s = seg
                s.referenceText = s.referenceText.trimmingCharacters(in: .whitespacesAndNewlines)
                return s
            }
            .filter { !$0.referenceText.isEmpty }
    }

    private func load() {
        guard !loaded, let doc = store.document(id: documentID) else { return }
        title = doc.title
        segments = doc.segments
        loaded = true
    }

    private func save() {
        guard var doc = store.document(id: documentID) else { return }
        doc.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? doc.title : title
        // Отредактированный фрагмент длиннее лимита снова делим на части.
        var result: [ReadingSegment] = []
        for seg in cleanedSegments {
            let parts = TextSegmenter.split(paragraph: seg.referenceText)
            if parts.count == 1 {
                var s = seg
                s.sequence = result.count
                result.append(s)
            } else {
                for part in parts {
                    result.append(ReadingSegment(id: UUID(), sequence: result.count, referenceText: part, pageNumber: seg.pageNumber))
                }
            }
        }
        doc.segments = result
        doc.completedSegments = min(doc.completedSegments, result.count)
        store.update(doc)
    }
}

#if DEBUG
#Preview {
    let store = AppStore.demo()
    return NavigationStack { TextReviewView(documentID: store.documents[0].id) }
        .environment(store)
        .environment(Router())
}
#endif
