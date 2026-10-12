import Foundation
import SwiftUI

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [SurveyProject] = []
    @Published var errorMessage: String?
    @Published private(set) var canWrite = true
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiangZhu", isDirectory: true)
        self.fileURL = fileURL ?? folder.appendingPathComponent("projects-v1.json")
        do {
            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                projects = try JSONDecoder().decode([SurveyProject].self, from: Data(contentsOf: self.fileURL))
                guard projects.allSatisfy(\.isValid), Set(projects.map(\.id)).count == projects.count else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            } else {
                projects = [.example]
                try persist(projects)
            }
        } catch {
            projects = []
            canWrite = false
            errorMessage = "无法读取本地项目，原文件已保留。请检查设备存储或恢复备份。\n\(error.localizedDescription)"
        }
    }
    func project(_ id: UUID) -> SurveyProject? { projects.first { $0.id == id } }
    @discardableResult
    func save(_ project: SurveyProject) -> Bool {
        guard project.isValid else { errorMessage = "项目包含无效尺寸或重复记录，请检查房间与门窗。"; return false }
        var copy = projects
        var project = project
        project.updatedAt = Date()
        if let index = copy.firstIndex(where: { $0.id == project.id }) { copy[index] = project }
        else { copy.insert(project, at: 0) }
        return commit(copy)
    }
    func delete(_ id: UUID) { _ = commit(projects.filter { $0.id != id }) }
    func importBackup(_ url: URL) -> Bool {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 10_000_000 else { throw CocoaError(.fileReadTooLarge) }
            var project = try JSONDecoder().decode(SurveyProject.self, from: Data(contentsOf: url))
            guard project.isValid else { throw CocoaError(.fileReadCorruptFile) }
            project.id = UUID(); project.name += "（恢复）"
            return save(project)
        } catch { errorMessage = "无法导入备份：\(error.localizedDescription)"; return false }
    }
    private func commit(_ newProjects: [SurveyProject]) -> Bool {
        guard canWrite else { errorMessage = "本地文件读取异常，为保护原数据，暂时不能写入。"; return false }
        do { try persist(newProjects); projects = newProjects; return true }
        catch { errorMessage = "保存失败：\(error.localizedDescription)"; return false }
    }
    private func persist(_ value: [SurveyProject]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: fileURL, options: .atomic)
    }
}
