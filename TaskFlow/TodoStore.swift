import Foundation
import SwiftUI

// 任务：标题必填，内容 = 文字描述 + 图片附件 + 录音附件
struct TaskItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var note = ""
    var imageNames: [String] = []
    var audioNames: [String] = []
    var isDone = false
    var createdAt = Date()

    enum CodingKeys: String, CodingKey {
        case id, title, note, imageNames, audioNames, isDone, createdAt
    }

    init(title: String, note: String = "", imageNames: [String] = [],
         audioNames: [String] = [], isDone: Bool = false, createdAt: Date = Date()) {
        self.title = title
        self.note = note
        self.imageNames = imageNames
        self.audioNames = audioNames
        self.isDone = isDone
        self.createdAt = createdAt
    }

    // 兼容旧版只有标题的 todoitems 数据
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        imageNames = try c.decodeIfPresent([String].self, forKey: .imageNames) ?? []
        audioNames = try c.decodeIfPresent([String].self, forKey: .audioNames) ?? []
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

@MainActor
final class TaskStore: ObservableObject {
    @Published var items: [TaskItem] {
        didSet { save() }
    }

    /// 旧版（UserDefaults）存储键，仅用于一次性迁移
    private static let legacyKey = "todoitems.v1"

    private static var storageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tasks.json")
    }

    static var attachmentsDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Attachments")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        if let data = try? Data(contentsOf: Self.storageURL),
           let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) {
            items = decoded
        } else if let legacy = UserDefaults.standard.data(forKey: Self.legacyKey),
                  let decoded = try? JSONDecoder().decode([TaskItem].self, from: legacy) {
            items = decoded   // 首次升级：迁移旧数据到文件存储
        } else {
            items = []
        }
    }

    // MARK: - 增删改

    func add(_ item: TaskItem) {
        items.insert(item, at: 0)
    }

    func update(_ item: TaskItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    func toggle(_ item: TaskItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isDone.toggle()
    }

    func remove(with ids: Set<TaskItem.ID>) {
        for item in items where ids.contains(item.id) {
            Self.deleteAttachmentFiles(of: item)
        }
        items.removeAll { ids.contains($0.id) }
    }

    // MARK: - 附件文件

    static func url(for fileName: String) -> URL {
        attachmentsDir.appendingPathComponent(fileName)
    }

    @discardableResult
    static func saveImage(_ data: Data) -> String {
        let name = UUID().uuidString + ".jpg"
        try? data.write(to: url(for: name), options: .atomic)
        return name
    }

    static func deleteFiles(_ names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(at: url(for: name))
        }
    }

    static func deleteAttachmentFiles(of item: TaskItem) {
        deleteFiles(item.imageNames)
        deleteFiles(item.audioNames)
    }

    // MARK: - 持久化

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: Self.storageURL, options: .atomic)
        }
    }
}
