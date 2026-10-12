import Foundation

struct PlanPoint: Codable, Hashable {
    var x: Double
    var y: Double
    func distance(to other: PlanPoint) -> Double { hypot(x - other.x, y - other.y) }
}

enum OpeningKind: String, Codable, CaseIterable, Identifiable {
    case door = "门", window = "窗", passage = "垭口"
    var id: String { rawValue }
    var symbol: String { self == .window ? "window.horizontal" : "door.left.hand.open" }
}

struct Opening: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: OpeningKind
    var edge: Int
    /// Distance along the edge from its first vertex, in metres.
    var offset: Double
    var width: Double
    var height: Double
    var sill: Double = 0
}

enum RoomSource: String, Codable {
    case manual = "手动测量", lidar = "LiDAR 扫描", example = "示例数据"
}

struct SurveyRoom: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var vertices: [PlanPoint]
    var height: Double
    var openings: [Opening] = []
    var notes: String = ""
    var source: RoomSource = .manual
    var measuredAt = Date()

    var area: Double { Self.area(of: vertices) }
    var perimeter: Double {
        guard vertices.count >= 3 else { return 0 }
        return vertices.indices.reduce(0) { $0 + edgeLength($1) }
    }
    var wallArea: Double { max(0, perimeter * height - openings.reduce(0) { $0 + $1.width * $1.height }) }
    var bounds: (width: Double, depth: Double) {
        (max(0.01, (vertices.map(\.x).max() ?? 0) - (vertices.map(\.x).min() ?? 0)),
         max(0.01, (vertices.map(\.y).max() ?? 0) - (vertices.map(\.y).min() ?? 0)))
    }
    func edgeLength(_ edge: Int) -> Double {
        guard vertices.indices.contains(edge), !vertices.isEmpty else { return 0 }
        return vertices[edge].distance(to: vertices[(edge + 1) % vertices.count])
    }
    func openingProblem(_ opening: Opening, excluding id: UUID? = nil) -> String? {
        guard vertices.indices.contains(opening.edge) else { return "请选择有效墙面。" }
        guard [opening.offset, opening.width, opening.height, opening.sill].allSatisfy(\.isFinite),
              opening.width > 0, opening.height > 0, opening.offset >= 0, opening.sill >= 0 else {
            return "尺寸必须大于 0，距墙角与窗台高度不能为负。"
        }
        guard opening.offset + opening.width <= edgeLength(opening.edge) + 0.0001 else { return "门窗超出了这面墙，请调整宽度或距墙角距离。" }
        guard opening.height + opening.sill <= height + 0.0001 else { return "门窗顶部超出了层高。" }
        let overlaps = openings.contains {
            $0.id != id && $0.edge == opening.edge &&
            max($0.offset, opening.offset) < min($0.offset + $0.width, opening.offset + opening.width) - 0.0001 &&
            max($0.sill, opening.sill) < min($0.sill + $0.height, opening.sill + opening.height) - 0.0001
        }
        return overlaps ? "该位置与已有门窗重叠。" : nil
    }
    static func area(of points: [PlanPoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        return abs(points.indices.reduce(0) { sum, i in
            let a = points[i], b = points[(i + 1) % points.count]
            return sum + a.x * b.y - b.x * a.y
        }) / 2
    }
    static func validPolygon(_ points: [PlanPoint]) -> Bool {
        guard points.count >= 3, points.count <= 30,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 100 && abs($0.y) <= 100 }),
              Set(points).count == points.count, area(of: points) >= 0.01 else { return false }
        func cross(_ a: PlanPoint, _ b: PlanPoint, _ c: PlanPoint) -> Double {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        func onSegment(_ a: PlanPoint, _ b: PlanPoint, _ p: PlanPoint) -> Bool {
            abs(cross(a, b, p)) < 1e-8 && p.x >= min(a.x, b.x) - 1e-8 && p.x <= max(a.x, b.x) + 1e-8 &&
                p.y >= min(a.y, b.y) - 1e-8 && p.y <= max(a.y, b.y) + 1e-8
        }
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            if a.distance(to: b) < 0.01 { return false }
            let c = points[(i + 2) % points.count]
            if onSegment(a, b, c) || onSegment(b, c, a) { return false }
            for j in points.indices where j > i && j != i + 1 && !(i == 0 && j == points.count - 1) {
                let c = points[j], d = points[(j + 1) % points.count]
                if (cross(a, b, c) * cross(a, b, d) < 0 && cross(c, d, a) * cross(c, d, b) < 0) ||
                    onSegment(a, b, c) || onSegment(a, b, d) || onSegment(c, d, a) || onSegment(c, d, b) { return false }
            }
        }
        return true
    }
    static func rectangle(width: Double, depth: Double) -> [PlanPoint] {
        [.init(x: 0, y: 0), .init(x: width, y: 0), .init(x: width, y: depth), .init(x: 0, y: depth)]
    }
    /// Remove a rectangle at the upper-right corner of the displayed plan.
    static func lShape(width: Double, depth: Double, cutWidth: Double, cutDepth: Double) -> [PlanPoint] {
        [.init(x: 0, y: 0), .init(x: width - cutWidth, y: 0),
         .init(x: width - cutWidth, y: cutDepth), .init(x: width, y: cutDepth),
         .init(x: width, y: depth), .init(x: 0, y: depth)]
    }
}

struct SurveyProject: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var address: String = ""
    var rooms: [SurveyRoom] = []
    var updatedAt = Date()
    var isExample = false
    var area: Double { rooms.reduce(0) { $0 + $1.area } }
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Set(rooms.map(\.id)).count == rooms.count && rooms.allSatisfy { room in
            !room.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            SurveyRoom.validPolygon(room.vertices) && room.height.isFinite && room.height >= 1 && room.height <= 20 &&
            Set(room.openings.map(\.id)).count == room.openings.count &&
            room.openings.allSatisfy { room.openingProblem($0, excluding: $0.id) == nil }
        }
    }

    static var example: SurveyProject {
        SurveyProject(name: "理想家的第一张图", address: "示例项目 · 可编辑或删除", rooms: [
            SurveyRoom(name: "客厅", vertices: SurveyRoom.rectangle(width: 5.2, depth: 4.1), height: 2.8,
                openings: [Opening(kind: .window, edge: 0, offset: 1.2, width: 2.4, height: 1.5, sill: 0.9),
                           Opening(kind: .door, edge: 2, offset: 3.7, width: 0.9, height: 2.1)],
                notes: "示例：入户侧墙预留玄关柜，窗边保留插座。", source: .example),
            SurveyRoom(name: "主卧", vertices: SurveyRoom.rectangle(width: 3.8, depth: 3.5), height: 2.8,
                openings: [Opening(kind: .window, edge: 0, offset: 0.9, width: 1.8, height: 1.5, sill: 0.9)], source: .example),
            SurveyRoom(name: "厨房", vertices: SurveyRoom.lShape(width: 3.2, depth: 2.8, cutWidth: 1, cutDepth: 1), height: 2.8,
                notes: "示例：右上方缺角为管井。", source: .example)
        ], isExample: true)
    }
}

enum DimensionUnit: String, CaseIterable, Identifiable {
    case metres = "m", millimetres = "mm"
    var id: String { rawValue }
    func format(_ value: Double) -> String {
        self == .metres ? String(format: "%.2f m", value) : String(format: "%.0f mm", value * 1000)
    }
}

func decimalValue(_ text: String) -> Double? {
    guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")), value.isFinite else { return nil }
    return value
}
