import SwiftUI
import UIKit

@MainActor
enum SurveyExporter {
    enum ExportError: LocalizedError {
        case emptyProject, renderFailed
        var errorDescription: String? {
            switch self {
            case .emptyProject: "请先添加至少一个房间。"
            case .renderFailed: "平面图渲染失败，请重新打开项目再导出。"
            }
        }
    }
    static func backup(project: SurveyProject) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = try exportURL(name: project.name, extension: "json")
        try encoder.encode(project).write(to: url, options: .atomic)
        return url
    }

    static func pdf(project: SurveyProject) throws -> URL {
        guard !project.rooms.isEmpty else { throw ExportError.emptyProject }
        let images: [UIImage] = try project.rooms.map { room in
            let renderer = ImageRenderer(content: FloorPlanView(room: room).frame(width: 515, height: 300))
            renderer.scale = 2
            guard let image = renderer.uiImage else { throw ExportError.renderFailed }
            return image
        }
        let url = try exportURL(name: project.name, extension: "pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let ink = UIColor(red: 0.13, green: 0.24, blue: 0.22, alpha: 1)
        var page = 0
        try renderer.writePDF(to: url) { context in
            var y: CGFloat = 0
            func text(_ string: String, font: UIFont, at rect: CGRect, color: UIColor = .darkGray) {
                (string as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color])
            }
            func startPage() {
                context.beginPage(); page += 1; y = 98
                text("量筑  /  装修测绘记录", font: .boldSystemFont(ofSize: 22), at: CGRect(x: 40, y: 35, width: 515, height: 30), color: ink)
                text("\(project.name) · \(Date().formatted(date: .numeric, time: .omitted))", font: .systemFont(ofSize: 10), at: CGRect(x: 40, y: 70, width: 515, height: 22))
                text("现场尺寸请复核 · 图纸为示意方向 · 尺寸单位：米", font: .systemFont(ofSize: 9), at: CGRect(x: 40, y: 803, width: 440, height: 16))
                text("\(page)", font: .systemFont(ofSize: 10), at: CGRect(x: 525, y: 803, width: 30, height: 16))
            }
            func ensure(_ height: CGFloat) { if y + height > 778 { startPage() } }
            func line(_ string: String, bold: Bool = false, size: CGFloat = 11) {
                let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
                let box = (string as NSString).boundingRect(with: CGSize(width: 515, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
                let height = ceil(box.height) + 8
                ensure(height)
                text(string, font: font, at: CGRect(x: 40, y: y, width: 515, height: height), color: bold ? ink : .darkGray)
                y += height
            }
            for (index, room) in project.rooms.enumerated() {
                startPage()
                line(room.name, bold: true, size: 20)
                if !project.address.isEmpty { line("地址：\(project.address)") }
                line("来源：\(room.source.rawValue)   记录：\(room.measuredAt.formatted(date: .numeric, time: .shortened))")
                ensure(310)
                images[index].draw(in: CGRect(x: 40, y: y, width: 515, height: 300)); y += 310
                line(String(format: "净地面 %.2f m²    周长 %.2f m    层高 %.2f m    净墙面 %.2f m²", room.area, room.perimeter, room.height, room.wallArea), bold: true)
                line("墙面净长度", bold: true)
                let wallRows = room.vertices.indices.map { "W\($0 + 1)  \(DimensionUnit.metres.format(room.edgeLength($0)))" }
                for start in stride(from: 0, to: wallRows.count, by: 4) { line(wallRows[start..<min(start + 4, wallRows.count)].joined(separator: "     ")) }
                line("门窗 / 垭口记录（\(room.openings.count)）", bold: true)
                if room.openings.isEmpty { line("无门窗记录") }
                for opening in room.openings {
                    line(String(format: "%@ · W%d   宽 %.3f × 高 %.3f   距起点 %.3f   离地 %.3f m", opening.kind.rawValue, opening.edge + 1, opening.width, opening.height, opening.offset, opening.sill))
                }
                if !room.notes.isEmpty {
                    line("现场备注", bold: true)
                    let chars = Array(room.notes)
                    for start in stride(from: 0, to: chars.count, by: 150) { line(String(chars[start..<min(start + 150, chars.count)])) }
                }
                line("净墙面 = 周长 × 层高 − 门窗及垭口面积；不含材料损耗、梁柱或踢脚线。", size: 9)
            }
        }
        return url
    }
    private static func exportURL(name: String, extension suffix: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LiangZhu-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let clean = String(name.map { "/\\:?%*|\"<>\n\r".contains($0) ? "_" : $0 }.prefix(60))
        return folder.appendingPathComponent("\(clean.isEmpty ? "测绘记录" : clean).\(suffix)")
    }
}
