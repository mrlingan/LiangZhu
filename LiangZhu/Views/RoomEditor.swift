import SwiftUI

private enum RoomShape: String, CaseIterable, Identifiable {
    case rectangle = "矩形", lShape = "L 形", custom = "自定义"
    var id: String { rawValue }
}
private struct VertexInput: Identifiable {
    var id = UUID()
    var x: String
    var y: String
}

struct RoomEditor: View {
    @Environment(\.dismiss) private var dismiss
    var existing: SurveyRoom?
    var onSave: (SurveyRoom) -> Bool
    @State private var name = ""
    @State private var shape: RoomShape = .rectangle
    @State private var width = ""
    @State private var depth = ""
    @State private var height = "2.80"
    @State private var cutWidth = "1.00"
    @State private var cutDepth = "1.00"
    @State private var coordinates: [VertexInput] = []
    @State private var notes = ""
    @State private var validation: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("房间信息") {
                    TextField("房间名称，例如：客厅", text: $name)
                    Picker("轮廓", selection: $shape) { ForEach(RoomShape.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                }
                Section("尺寸（米）") {
                    if shape != .custom {
                        DimensionField(title: "宽度", text: $width)
                        DimensionField(title: "进深", text: $depth)
                        if shape == .lShape {
                            DimensionField(title: "右上缺角宽度", text: $cutWidth)
                            DimensionField(title: "右上缺角进深", text: $cutDepth)
                        }
                    }
                    DimensionField(title: "净层高", text: $height)
                }
                if shape == .custom {
                    Section {
                        ForEach(Array(coordinates.enumerated()), id: \.element.id) { index, item in
                            HStack {
                                Text("P\(index + 1)").font(.caption.monospaced()).frame(width: 30)
                                TextField("X", text: $coordinates[index].x).keyboardType(.numbersAndPunctuation)
                                TextField("Y", text: $coordinates[index].y).keyboardType(.numbersAndPunctuation)
                                Button(role: .destructive) { coordinates.removeAll { $0.id == item.id } } label: {
                                    Image(systemName: "minus.circle")
                                }.buttonStyle(.borderless).disabled(coordinates.count <= 3)
                            }
                        }
                        Button("添加顶点", systemImage: "plus") { coordinates.append(VertexInput(x: "", y: "")) }.disabled(coordinates.count >= 30)
                    } header: { Text("轮廓顶点 · X / Y（米）") } footer: {
                        Text("从任意墙角开始，沿边界依次输入顶点；末点自动连接首点。W1 对应 P1→P2。允许负坐标，请勿交叉。")
                    }
                }
                if let draft = draftRoom {
                    Section("轮廓预览") {
                        FloorPlanView(room: draft).frame(height: 260).listRowInsets(EdgeInsets())
                        LabeledContent("净地面面积", value: String(format: "%.2f m²", draft.area))
                    }
                }
                Section("现场备注") {
                    TextEditor(text: $notes).frame(minHeight: 90)
                }
                if existing?.openings.isEmpty == false {
                    Section { Text("修改轮廓后会复核现有门窗的位置。若墙面顺序改变，请同时检查门窗对应的墙号。")
                        .font(.footnote).foregroundStyle(.secondary) }
                }
                if let validation { Section { Text(validation).foregroundStyle(.red) } }
            }.navigationTitle(existing == nil ? "添加房间" : "编辑房间").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).fontWeight(.semibold) }
                }
                .onAppear(perform: load)
                .onChange(of: shape) { oldShape, newShape in
                    if newShape == .custom, coordinates.isEmpty {
                        let w = decimalValue(width) ?? 4, d = decimalValue(depth) ?? 3
                        let cw = decimalValue(cutWidth) ?? 1, cd = decimalValue(cutDepth) ?? 1
                        let points = oldShape == .lShape && cw < w && cd < d ?
                            SurveyRoom.lShape(width: w, depth: d, cutWidth: cw, cutDepth: cd) : SurveyRoom.rectangle(width: w, depth: d)
                        coordinates = points.map { VertexInput(x: String(format: "%.3f", $0.x), y: String(format: "%.3f", $0.y)) }
                    }
                }
        }.tint(Palette.green)
    }
    private var draftRoom: SurveyRoom? {
        guard let h = decimalValue(height), h >= 1, h <= 20 else { return nil }
        var points: [PlanPoint]
        if shape == .custom {
            points = coordinates.compactMap { input in
                guard let x = decimalValue(input.x), let y = decimalValue(input.y) else { return nil }
                return PlanPoint(x: x, y: y)
            }
            guard points.count == coordinates.count else { return nil }
        } else {
            guard let w = decimalValue(width), let d = decimalValue(depth), w >= 0.1, d >= 0.1, w <= 100, d <= 100 else { return nil }
            if shape == .lShape {
                guard let cw = decimalValue(cutWidth), let cd = decimalValue(cutDepth), cw >= 0.1, cd >= 0.1, cw < w, cd < d else { return nil }
                points = SurveyRoom.lShape(width: w, depth: d, cutWidth: cw, cutDepth: cd)
            } else { points = SurveyRoom.rectangle(width: w, depth: d) }
        }
        guard SurveyRoom.validPolygon(points) else { return nil }
        var room = existing ?? SurveyRoom(name: name, vertices: points, height: h)
        room.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        room.vertices = points; room.height = h; room.notes = notes
        return room
    }
    private func load() {
        guard let existing else { return }
        name = existing.name; height = String(existing.height); notes = existing.notes
        width = String(existing.bounds.width); depth = String(existing.bounds.depth)
        if existing.vertices != SurveyRoom.rectangle(width: existing.bounds.width, depth: existing.bounds.depth) {
            shape = .custom
            coordinates = existing.vertices.map { VertexInput(x: String($0.x), y: String($0.y)) }
        }
    }
    private func save() {
        guard var draft = draftRoom else {
            validation = "请填写有效尺寸：宽度 / 进深 0.1–100 m，层高 1–20 m；自定义轮廓至少 3 个不重复、不交叉的顶点。"; return
        }
        guard !draft.name.isEmpty else { validation = "请填写房间名称。"; return }
        for opening in draft.openings {
            if let problem = draft.openingProblem(opening, excluding: opening.id) {
                validation = "现有\(opening.kind.rawValue)（W\(opening.edge + 1)）：\(problem) 请先修改或删除此门窗。"; return
            }
        }
        if let existing, existing.vertices != draft.vertices || existing.height != draft.height {
            draft.source = .manual
        }
        draft.measuredAt = Date()
        if onSave(draft) { dismiss() }
    }
}

struct DimensionField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0.00", text: $text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110)
                .accessibilityLabel(title)
            Text("m").foregroundStyle(.secondary).font(.caption)
        }
    }
}

struct OpeningEditor: View {
    @Environment(\.dismiss) private var dismiss
    let room: SurveyRoom
    var existing: Opening?
    var onSave: (Opening) -> Bool
    @State private var kind: OpeningKind = .door
    @State private var edge = 0
    @State private var offset = "0.00"
    @State private var width = "0.90"
    @State private var height = "2.10"
    @State private var sill = "0.00"
    @State private var validation: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("类型与位置") {
                    Picker("类型", selection: $kind) { ForEach(OpeningKind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    Picker("所在墙面", selection: $edge) {
                        ForEach(room.vertices.indices, id: \.self) { i in
                            Text("W\(i + 1) · \(DimensionUnit.metres.format(room.edgeLength(i)))").tag(i)
                        }
                    }
                    DimensionField(title: "距起点墙角", text: $offset)
                }
                Section("净尺寸（米）") {
                    DimensionField(title: "宽度", text: $width)
                    DimensionField(title: "高度", text: $height)
                    if kind == .window { DimensionField(title: "窗台离地高度", text: $sill) }
                }
                Section {
                    FloorPlanView(room: room).frame(height: 250).listRowInsets(EdgeInsets())
                } footer: { Text("墙面按 P1→P2→… 的顺序编号。距墙角从该墙面的起点量起，图纸顶部为示意方向。") }
                if let validation { Section { Text(validation).foregroundStyle(.red) } }
            }.navigationTitle(existing == nil ? "添加门窗" : "编辑门窗").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") {
                        guard let o = decimalValue(offset), let w = decimalValue(width), let h = decimalValue(height),
                              let s = decimalValue(kind == .window ? sill : "0") else { validation = "请填写有效的数字尺寸。"; return }
                        let opening = Opening(id: existing?.id ?? UUID(), kind: kind, edge: edge, offset: o, width: w, height: h, sill: s)
                        if let problem = room.openingProblem(opening, excluding: existing?.id) { validation = problem; return }
                        if onSave(opening) { dismiss() }
                    } }
                }
                .onAppear {
                    if let existing {
                        kind = existing.kind; edge = existing.edge; offset = String(existing.offset)
                        width = String(existing.width); height = String(existing.height); sill = String(existing.sill)
                    }
                }
                .onChange(of: kind) { _, kind in
                    if existing == nil { height = kind == .window ? "1.50" : "2.10"; width = kind == .window ? "1.80" : "0.90"; sill = kind == .window ? "0.90" : "0.00" }
                }
        }.tint(Palette.green)
    }
}
