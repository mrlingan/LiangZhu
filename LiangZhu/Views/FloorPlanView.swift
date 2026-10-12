import SwiftUI

struct FloorPlanView: View {
    let room: SurveyRoom
    var unit: DimensionUnit = .metres
    var compact = false

    var body: some View {
        Canvas { context, size in
            let grid: CGFloat = compact ? 16 : 22
            var lines = Path()
            for x in stride(from: CGFloat(0), through: size.width, by: grid) {
                lines.move(to: CGPoint(x: x, y: 0)); lines.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: CGFloat(0), through: size.height, by: grid) {
                lines.move(to: CGPoint(x: 0, y: y)); lines.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(lines, with: .color(Palette.line.opacity(0.45)), lineWidth: 0.5)
            guard room.vertices.count >= 3 else { return }
            let margin: CGFloat = compact ? 18 : 58
            let scale = min(max(1, size.width - margin * 2) / room.bounds.width, max(1, size.height - margin * 2) / room.bounds.depth)
            let minX = room.vertices.map(\.x).min() ?? 0, minY = room.vertices.map(\.y).min() ?? 0
            let origin = CGPoint(x: (size.width - room.bounds.width * scale) / 2, y: (size.height - room.bounds.depth * scale) / 2)
            func point(_ p: PlanPoint) -> CGPoint { CGPoint(x: origin.x + (p.x - minX) * scale, y: origin.y + (p.y - minY) * scale) }
            let points = room.vertices.map(point)
            var outline = Path()
            outline.addLines(points); outline.closeSubpath()
            context.fill(outline, with: .color(Palette.green.opacity(0.08)))
            context.stroke(outline, with: .color(Palette.ink), style: StrokeStyle(lineWidth: compact ? 3 : 5, lineJoin: .miter))

            let signedArea = room.vertices.indices.reduce(0.0) { sum, i in
                let a = room.vertices[i], b = room.vertices[(i + 1) % points.count]
                return sum + a.x * b.y - b.x * a.y
            }
            for i in points.indices {
                let a = points[i], b = points[(i + 1) % points.count]
                let length = hypot(b.x - a.x, b.y - a.y)
                guard length > 0 else { continue }
                let dx = (b.x - a.x) / length, dy = (b.y - a.y) / length
                let sign: CGFloat = signedArea >= 0 ? 1 : -1
                let nx = dy * sign, ny = -dx * sign
                if !compact {
                    let gap: CGFloat = 24
                    let aa = CGPoint(x: a.x + nx * gap, y: a.y + ny * gap)
                    let bb = CGPoint(x: b.x + nx * gap, y: b.y + ny * gap)
                    var ruler = Path()
                    ruler.move(to: aa); ruler.addLine(to: bb)
                    for p in [aa, bb] {
                        ruler.move(to: CGPoint(x: p.x - nx * 4 - dx * 3, y: p.y - ny * 4 - dy * 3))
                        ruler.addLine(to: CGPoint(x: p.x + nx * 4 + dx * 3, y: p.y + ny * 4 + dy * 3))
                    }
                    context.stroke(ruler, with: .color(Palette.muted), lineWidth: 0.8)
                    let label = Text(unit.format(room.edgeLength(i))).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(Palette.ink)
                    context.draw(label, at: CGPoint(x: (aa.x + bb.x) / 2 + nx * 13, y: (aa.y + bb.y) / 2 + ny * 13))
                    context.draw(Text("W\(i + 1)").font(.system(size: 9, weight: .bold)).foregroundColor(Palette.muted),
                        at: CGPoint(x: (a.x + b.x) / 2 - nx * 13, y: (a.y + b.y) / 2 - ny * 13))
                }
                for opening in room.openings where opening.edge == i {
                    let start = CGPoint(x: a.x + dx * opening.offset * scale, y: a.y + dy * opening.offset * scale)
                    let end = CGPoint(x: start.x + dx * opening.width * scale, y: start.y + dy * opening.width * scale)
                    var gapPath = Path(); gapPath.move(to: start); gapPath.addLine(to: end)
                    context.stroke(gapPath, with: .color(Palette.background), lineWidth: compact ? 5 : 7)
                    if opening.kind == .window {
                        for offset: CGFloat in [-2, 2] {
                            var window = Path()
                            window.move(to: CGPoint(x: start.x + nx * offset, y: start.y + ny * offset))
                            window.addLine(to: CGPoint(x: end.x + nx * offset, y: end.y + ny * offset))
                            context.stroke(window, with: .color(Palette.green), lineWidth: 1.5)
                        }
                    } else if opening.kind == .door {
                        let radius = opening.width * scale
                        let leaf = CGPoint(x: start.x - nx * radius, y: start.y - ny * radius)
                        var door = Path(); door.move(to: start); door.addLine(to: leaf)
                        door.move(to: end)
                        door.addQuadCurve(to: leaf, control: CGPoint(x: end.x - nx * radius, y: end.y - ny * radius))
                        context.stroke(door, with: .color(Palette.orange), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    } else {
                        context.stroke(gapPath, with: .color(Palette.orange), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                    }
                }
            }
            if !compact, room.vertices.count == 4 {
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                context.draw(Text(room.name).font(.system(size: 16, weight: .semibold)).foregroundColor(Palette.ink), at: CGPoint(x: center.x, y: center.y - 10))
                context.draw(Text(String(format: "%.2f m²", room.area)).font(.system(size: 13, design: .rounded)).foregroundColor(Palette.muted), at: CGPoint(x: center.x, y: center.y + 14))
            }
            if !compact {
                for i in points.indices {
                    let p = points[i], before = points[(i + points.count - 1) % points.count], after = points[(i + 1) % points.count]
                    let l1 = max(1, hypot(before.x - p.x, before.y - p.y)), l2 = max(1, hypot(after.x - p.x, after.y - p.y))
                    let vx = (before.x - p.x) / l1 + (after.x - p.x) / l2
                    let vy = (before.y - p.y) / l1 + (after.y - p.y) / l2
                    let length = max(0.1, hypot(vx, vy))
                    let label = CGPoint(x: p.x + vx / length * 16, y: p.y + vy / length * 16)
                    context.draw(Text("P\(i + 1)").font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(Palette.muted), at: label)
                }
            }
        }
        .background(Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 14 : 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(room.name)平面图，\(room.vertices.count)面墙，面积\(String(format: "%.2f", room.area))平方米，\(room.openings.count)个门窗")
    }
}
