import SwiftUI

struct ContentView: View {
    @StateObject private var store = TaskStore()
    @State private var filter: Filter = .all
    @State private var showNewTask = false
    @State private var editingItem: TaskItem?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case active = "未完成"
        case done = "已完成"

        var id: String { rawValue }
    }

    private var filteredItems: [TaskItem] {
        switch filter {
        case .all: store.items
        case .active: store.items.filter { !$0.isDone }
        case .done: store.items.filter { $0.isDone }
        }
    }

    private var remainingCount: Int {
        store.items.filter { !$0.isDone }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredItems) { item in
                            TaskCard(item: item) {
                                store.toggle(item)
                            }
                            .onTapGesture { editingItem = item }
                            .contextMenu {
                                Button {
                                    store.toggle(item)
                                } label: {
                                    Label(item.isDone ? "标记为未完成" : "标记为已完成",
                                          systemImage: item.isDone ? "circle" : "checkmark.circle")
                                }
                                Button(role: .destructive) {
                                    store.remove(with: [item.id])
                                } label: {
                                    Label("删除任务", systemImage: "trash")
                                }
                            }
                        }

                        if !store.items.isEmpty {
                            Text("共 \(store.items.count) 项任务，\(remainingCount) 项未完成")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                if filteredItems.isEmpty {
                    ContentUnavailableView {
                        Label(store.items.isEmpty ? "还没有任务" : "没有符合条件的任务", systemImage: "checklist")
                    } description: {
                        Text(store.items.isEmpty ? "点右上角 + 创建你的第一个任务" : "换个筛选条件试试")
                    }
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle("待办清单")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewTask = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("筛选", selection: $filter) {
                            ForEach(Filter.allCases) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }
                        if store.items.contains(where: { $0.isDone }) {
                            Divider()
                            Button(role: .destructive) {
                                let doneIds = Set(store.items.filter(\.isDone).map(\.id))
                                store.remove(with: doneIds)
                            } label: {
                                Label("清除已完成", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showNewTask) {
                TaskEditorView(store: store, editing: nil)
            }
            .sheet(item: $editingItem) { item in
                TaskEditorView(store: store, editing: item)
            }
        }
    }
}

// MARK: - 任务卡片

struct TaskCard: View {
    let item: TaskItem
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: onToggle) {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.isDone ? .green : .secondary)
                }
                .buttonStyle(.plain)

                Text(item.title)
                    .font(.headline)
                    .strikethrough(item.isDone, color: .secondary)
                    .foregroundStyle(item.isDone ? .secondary : .primary)

                Spacer()

                Text(item.createdAt.formatted(.dateTime.month().day()))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !item.note.isEmpty {
                Text(item.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !item.imageNames.isEmpty {
                HStack(spacing: 8) {
                    ForEach(item.imageNames.prefix(3), id: \.self) { thumb($0) }
                    if item.imageNames.count > 3 {
                        Text("+\(item.imageNames.count - 3)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 56, height: 56)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            if !item.audioNames.isEmpty {
                Label("\(item.audioNames.count) 条录音", systemImage: "mic.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.blue.opacity(0.1)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private func thumb(_ name: String) -> some View {
        let url = TaskStore.url(for: name)
        let base: Image
        if let ui = UIImage(contentsOfFile: url.path) {
            base = Image(uiImage: ui)
        } else {
            base = Image(systemName: "photo")
        }
        return base
            .resizable()
            .scaledToFill()
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
