import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var model = ImportViewModel()
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showPaste = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                dropZone

                VStack(spacing: Theme.Spacing.s) {
                    if CameraPicker.isAvailable {
                        Button { showCamera = true } label: {
                            MenuRow(icon: "camera.fill", title: "Фото текста", subtitle: "Сфотографируйте страницу")
                        }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        MenuRow(icon: "photo.on.rectangle", title: "Из галереи", subtitle: "Скриншот или фото страницы")
                    }
                    Button { showFileImporter = true } label: {
                        MenuRow(icon: "icloud.fill", title: "iCloud Drive и Файлы", subtitle: "PDF, DOCX, TXT")
                    }
                    Button { showPaste = true } label: {
                        MenuRow(icon: "doc.on.clipboard.fill", title: "Вставить текст", subtitle: "Скопированный английский текст")
                    }
                }
                .buttonStyle(.plain)

                formats
            }
            .padding(Theme.Spacing.l)
        }
        .screenBackground()
        .navigationTitle("Загрузка текста")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isWorking)
        .overlay {
            if model.isWorking { workingOverlay }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: ImportViewModel.fileTypes) { result in
            Task { await finish(model.importFile(result)) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await finish(model.importPhoto(item)) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                Task { await finish(model.importCameraImage(image)) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showPaste) {
            PasteTextSheet { text in
                Task { await finish(model.importPasted(text)) }
            }
        }
        .alert("Не удалось загрузить", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func finish(_ document: SCDocument?) async {
        guard let document else { return }
        store.add(document)
        router.push(.textReview(documentID: document.id))
    }

    private var dropZone: some View {
        VStack(spacing: Theme.Spacing.l) {
            Image(systemName: "arrow.up.doc")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.Colors.accentLight)
                .frame(width: 76, height: 76)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.medium).fill(Theme.Colors.accent.opacity(0.14)))
            VStack(spacing: 6) {
                Text("Загрузите свой файл")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("PDF, Word (DOCX), TXT\nили фото текста")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Button("Выбрать файл") { showFileImporter = true }
                .buttonStyle(.primary)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .fill(Theme.Colors.surface.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .stroke(Theme.Colors.textTertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
        )
    }

    private var formats: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Поддерживаемые форматы")
                .font(.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
            HStack(spacing: Theme.Spacing.s) {
                ForEach(["PDF", "DOCX", "TXT", "JPG", "PNG", "HEIC"], id: \.self) { Chip(text: $0) }
            }
            Text("До \(ImportViewModel.maxFileMB) МБ. Текст читается на английском языке.")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var workingOverlay: some View {
        VStack(spacing: Theme.Spacing.m) {
            ProgressView().controlSize(.large).tint(Theme.Colors.accentLight)
            Text(model.progressText)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(Theme.Spacing.xl)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.large).fill(Theme.Colors.surface))
        .shadow(radius: 30)
    }
}

/// Лист для вставки скопированного текста.
struct PasteTextSheet: View {
    var onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(Theme.Spacing.m)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.medium).fill(Theme.Colors.surface))
                .padding(Theme.Spacing.l)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Вставьте английский текст…")
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .padding(Theme.Spacing.l + Theme.Spacing.m + 5)
                            .allowsHitTesting(false)
                    }
                }
                .screenBackground()
                .navigationTitle("Вставить текст")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") {
                            dismiss()
                            onDone(text)
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Вставить из буфера", systemImage: "doc.on.clipboard") {
                            if let s = UIPasteboard.general.string { text = s }
                        }
                    }
                }
                .onAppear { focused = true }
        }
        .presentationBackground(Theme.Colors.background)
    }
}

/// Системная камера (UIImagePickerController) для фото страницы.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { ImportView() }
        .environment(AppStore(persists: false))
        .environment(Router())
}
#endif
