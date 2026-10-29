import SwiftUI
import PhotosUI

// 新建 / 编辑任务：标题必填，内容可包含文字、图片、录音
struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TaskStore
    let editing: TaskItem?   // nil = 新建

    @State private var title = ""
    @State private var note = ""
    @State private var imageNames: [String] = []
    @State private var audioNames: [String] = []

    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var loadingPhotos = false
    @StateObject private var recorder = AudioRecorder()

    // 本次会话新产生的附件（取消时清理，避免留下孤儿文件）
    @State private var newFiles: [String] = []
    // 编辑前已有的附件（保存时清理被移除的）
    @State private var originalImages: [String] = []
    @State private var originalAudios: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("任务标题（必填）", text: $title)
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("标题是必填的，填写后才能保存")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("标题")
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $note)
                            .frame(minHeight: 110)
                        if note.isEmpty {
                            Text("详细描述、想法、补充说明…")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                } header: {
                    Text("文字内容")
                }

                Section {
                    PhotosPicker(selection: $pickedPhotos, maxSelectionCount: 10, matching: .images) {
                        Label("添加图片", systemImage: "photo.on.rectangle.angled")
                    }
                    if loadingPhotos {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在导入图片…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !imageNames.isEmpty {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(imageNames, id: \.self) { name in
                                ZStack(alignment: .topTrailing) {
                                    imageView(name)
                                        .frame(height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Button {
                                        imageNames.removeAll { $0 == name }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.body)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .offset(x: 4, y: -4)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("图片")
                }

                Section {
                    RecordRow(recorder: recorder) { name in
                        audioNames.append(name)
                        newFiles.append(name)
                    }
                    ForEach(audioNames, id: \.self) { name in
                        AudioPlayerRow(fileName: name)
                    }
                    .onDelete { offsets in
                        audioNames.remove(atOffsets: offsets)
                    }
                    if audioNames.isEmpty {
                        Text("还没有录音")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } header: {
                    Text("录音")
                }
            }
            .navigationTitle(editing == nil ? "新建任务" : "编辑任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: loadForEditing)
            .onChange(of: pickedPhotos) { _, items in
                importPhotos(items)
            }
        }
    }

    // MARK: - 私有逻辑

    private func loadForEditing() {
        guard let item = editing else { return }
        title = item.title
        note = item.note
        imageNames = item.imageNames
        audioNames = item.audioNames
        originalImages = item.imageNames
        originalAudios = item.audioNames
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        loadingPhotos = true
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let name = TaskStore.saveImage(data)
                    imageNames.append(name)
                    newFiles.append(name)
                }
            }
            loadingPhotos = false
            pickedPhotos = []
        }
    }

    private func save() {
        if recorder.isRecording { _ = recorder.stop() }
        let item = TaskItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            note: note,
                            imageNames: imageNames,
                            audioNames: audioNames,
                            isDone: editing?.isDone ?? false,
                            createdAt: editing?.createdAt ?? Date())
        if let editing {
            var updated = item
            updated.id = editing.id
            store.update(updated)
            // 清理被删除的旧附件文件
            TaskStore.deleteFiles(originalImages.filter { !imageNames.contains($0) })
            TaskStore.deleteFiles(originalAudios.filter { !audioNames.contains($0) })
        } else {
            store.add(item)
        }
        dismiss()
    }

    private func cancel() {
        if recorder.isRecording { _ = recorder.stop() }
        TaskStore.deleteFiles(newFiles)   // 丢弃本次新增的附件
        dismiss()
    }

    private func imageView(_ name: String) -> some View {
        let url = TaskStore.url(for: name)
        let base: Image
        if let ui = UIImage(contentsOfFile: url.path) {
            base = Image(uiImage: ui)
        } else {
            base = Image(systemName: "photo")
        }
        return base.resizable().scaledToFill()
    }
}
