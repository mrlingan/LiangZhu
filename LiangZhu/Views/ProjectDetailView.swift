import SwiftUI
import UniformTypeIdentifiers

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ProjectDetailView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    @State private var editing = false
    @State private var addingRoom = false
    @State private var scanning = false
    @State private var sharedFile: SharedFile?
    @State private var exportError: String?
    @State private var deleting = false
    var body: some View {
        Group {
            if let project = store.project(projectID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(project.name).font(.system(size: 28, weight: .bold))
                            Text(project.address.isEmpty ? "记录现场，让装修有据可依" : project.address).font(.subheadline).foregroundStyle(Palette.muted)
                            if project.isExample {
                                Label("这是示例项目，尺寸不代表你的房屋", systemImage: "info.circle").font(.caption).foregroundStyle(Palette.orange)
                            }
                        }
                        Card {
                            HStack {
                                Metric(value: String(format: "%.2f", project.area), label: "净地面 m²")
                                Metric(value: "\(project.rooms.count)", label: "房间")
                                Metric(value: "\(project.rooms.reduce(0) { $0 + $1.openings.count })", label: "门窗 / 垭口")
                            }
                        }
                        HStack {
                            Text("房间记录").font(.title3.bold())
                            Spacer()
                            Menu {
                                Button("手动记录房间", systemImage: "ruler") { addingRoom = true }
                                Button("LiDAR 扫描房间", systemImage: "viewfinder") { scanning = true }
                            } label: { Label("添加", systemImage: "plus").font(.subheadline.bold()) }
                        }
                        if project.rooms.isEmpty {
                            Card {
                                VStack(spacing: 18) {
                                    Image(systemName: "square.dashed").font(.system(size: 42, weight: .light)).foregroundStyle(Palette.green)
                                    Text("从一间房的尺寸开始").font(.headline)
                                    Text("测量内净宽度、进深和层高，再标注门窗。").font(.caption).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                                    PrimaryButton(title: "手动记录房间", symbol: "plus") { addingRoom = true }
                                }.frame(maxWidth: .infinity).padding(.vertical, 10)
                            }
                        }
                        ForEach(project.rooms) { room in
                            NavigationLink { RoomDetailView(projectID: projectID, roomID: room.id) } label: {
                                Card {
                                    HStack(spacing: 17) {
                                        FloorPlanView(room: room, compact: true).frame(width: 100, height: 100)
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(room.name).font(.headline)
                                            Text(String(format: "%.2f m²", room.area)).font(.system(size: 22, weight: .medium, design: .rounded))
                                            Text("\(room.openings.count) 个门窗 · \(room.source.rawValue)").font(.caption2).foregroundStyle(Palette.muted)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                        Text("面积按各房间轮廓相加，不含墙体。每个房间单独出图。").font(.caption).foregroundStyle(Palette.muted)
                    }.padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
                }.background(Palette.background).foregroundStyle(Palette.ink)
                    .navigationTitle("项目").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button("编辑项目信息", systemImage: "pencil") { editing = true }
                                Button("导出测绘 PDF", systemImage: "doc.richtext") { export(project, pdf: true) }.disabled(project.rooms.isEmpty)
                                Button("导出 JSON 备份", systemImage: "square.and.arrow.up") { export(project, pdf: false) }
                                Button("删除项目", systemImage: "trash", role: .destructive) { deleting = true }
                            } label: { Image(systemName: "ellipsis.circle") }
                        }
                    }
                    .sheet(isPresented: $editing) { ProjectEditor(existing: project) { store.save($0) } }
                    .sheet(isPresented: $addingRoom) { RoomEditor { add($0) } }
                    .fullScreenCover(isPresented: $scanning) { RoomScanView { add($0) } }
                    .sheet(item: $sharedFile) { ShareSheet(url: $0.url) }
                    .alert("导出失败", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                        Button("知道了", role: .cancel) { exportError = nil }
                    } message: { Text(exportError ?? "") }
                    .alert("删除整个项目？", isPresented: $deleting) {
                        Button("删除", role: .destructive) { store.delete(projectID); if store.project(projectID) == nil { dismiss() } }
                        Button("取消", role: .cancel) { }
                    } message: { Text("所有房间与门窗记录将一并删除。建议先导出备份。") }
            } else { ContentUnavailableView("项目已删除", systemImage: "house") }
        }
    }
    private func add(_ room: SurveyRoom) -> Bool {
        guard var project = store.project(projectID) else { return false }
        project.rooms.append(room)
        return store.save(project)
    }
    private func export(_ project: SurveyProject, pdf: Bool) {
        do { sharedFile = SharedFile(url: try pdf ? SurveyExporter.pdf(project: project) : SurveyExporter.backup(project: project)) }
        catch { exportError = error.localizedDescription }
    }
}

struct RoomDetailView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    let roomID: UUID
    @AppStorage("dimensionUnit") private var unitString = DimensionUnit.metres.rawValue
    @State private var editingRoom = false
    @State private var addingOpening = false
    @State private var editingOpening: Opening?
    @State private var deletingRoom = false
    @State private var deletingOpening: Opening?
    private var room: SurveyRoom? { store.project(projectID)?.rooms.first { $0.id == roomID } }
    private var unit: DimensionUnit { DimensionUnit(rawValue: unitString) ?? .metres }

    var body: some View {
        Group {
            if let room {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(room.name).font(.system(size: 30, weight: .bold))
                                Label(room.source.rawValue, systemImage: room.source == .lidar ? "viewfinder" : "ruler")
                                    .font(.caption).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Picker("图纸单位", selection: $unitString) {
                                ForEach(DimensionUnit.allCases) { Text($0.rawValue).tag($0.rawValue) }
                            }.pickerStyle(.segmented).frame(width: 108)
                        }
                        VStack(spacing: 12) {
                            FloorPlanView(room: room, unit: unit).frame(height: 340)
                            HStack(spacing: 20) {
                                Label("门 / 垭口", systemImage: "minus").foregroundStyle(Palette.orange)
                                Label("窗", systemImage: "equal").foregroundStyle(Palette.green)
                                Spacer()
                                Text("示意方向 · 按比例").foregroundStyle(Palette.muted)
                            }.font(.caption2)
                        }
                        Card {
                            VStack(spacing: 20) {
                                HStack {
                                    Metric(value: String(format: "%.2f", room.area), label: "净地面 m²")
                                    Metric(value: String(format: "%.2f", room.perimeter), label: "周长 m")
                                    Metric(value: String(format: "%.2f", room.height), label: "层高 m")
                                }
                                Divider()
                                HStack {
                                    Text("扣除门窗后的墙面").font(.caption).foregroundStyle(Palette.muted)
                                    Spacer()
                                    Text(String(format: "%.2f m²", room.wallArea)).font(.headline.monospacedDigit())
                                }
                            }
                        }
                        HStack {
                            Text("门窗与垭口").font(.title3.bold())
                            Spacer()
                            Button { addingOpening = true } label: { Label("添加", systemImage: "plus").font(.subheadline.bold()) }
                        }
                        if room.openings.isEmpty {
                            Button { addingOpening = true } label: {
                                Card { Label("记录第一个门窗的位置与尺寸", systemImage: "plus.circle").font(.subheadline) }
                            }.buttonStyle(.plain)
                        }
                        ForEach(room.openings) { opening in
                            Button { editingOpening = opening } label: {
                                Card {
                                    HStack(alignment: .top, spacing: 14) {
                                        Image(systemName: opening.kind.symbol).font(.title2).foregroundStyle(opening.kind == .window ? Palette.green : Palette.orange).frame(width: 28)
                                        VStack(alignment: .leading, spacing: 7) {
                                            Text("\(opening.kind.rawValue) · W\(opening.edge + 1)").font(.headline)
                                            Text("宽 \(unit.format(opening.width)) × 高 \(unit.format(opening.height))").font(.caption).foregroundStyle(Palette.muted)
                                            Text("距起点 \(unit.format(opening.offset))" + (opening.kind == .window ? " · 窗台 \(unit.format(opening.sill))" : ""))
                                                .font(.caption2).foregroundStyle(Palette.muted)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "pencil").font(.caption).foregroundStyle(Palette.muted)
                                    }
                                }
                            }.buttonStyle(.plain).contextMenu {
                                Button("删除\(opening.kind.rawValue)", systemImage: "trash", role: .destructive) { deletingOpening = opening }
                            }
                        }
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("现场备注", systemImage: "square.and.pencil").font(.headline)
                                Text(room.notes.isEmpty ? "还没有备注，点击右上角编辑房间添加。" : room.notes)
                                    .font(.subheadline).foregroundStyle(Palette.muted)
                            }
                        }
                        Text("记录时间：\(room.measuredAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(Palette.muted)
                    }.padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
                }.background(Palette.background).foregroundStyle(Palette.ink)
                    .navigationTitle("房间测绘").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button("编辑房间与尺寸", systemImage: "pencil") { editingRoom = true }
                                Button("删除房间", systemImage: "trash", role: .destructive) { deletingRoom = true }
                            } label: { Image(systemName: "ellipsis.circle") }
                        }
                    }
                    .sheet(isPresented: $editingRoom) { RoomEditor(existing: room, onSave: save) }
                    .sheet(isPresented: $addingOpening) { OpeningEditor(room: room) { saveOpening($0) } }
                    .sheet(item: $editingOpening) { OpeningEditor(room: room, existing: $0) { saveOpening($0) } }
                    .alert("删除房间？", isPresented: $deletingRoom) {
                        Button("删除", role: .destructive) {
                            guard var project = store.project(projectID) else { return }
                            project.rooms.removeAll { $0.id == roomID }
                            if store.save(project) { dismiss() }
                        }
                        Button("取消", role: .cancel) { }
                    } message: { Text("此房间的尺寸、门窗与备注会一并删除。") }
                    .alert("删除这个门窗记录？", isPresented: Binding(get: { deletingOpening != nil }, set: { if !$0 { deletingOpening = nil } })) {
                        Button("删除", role: .destructive) {
                            if var latest = self.room, let opening = deletingOpening {
                                latest.openings.removeAll { $0.id == opening.id }; _ = save(latest)
                            }
                            deletingOpening = nil
                        }
                        Button("取消", role: .cancel) { deletingOpening = nil }
                    }
            } else { ContentUnavailableView("房间已删除", systemImage: "square.dashed") }
        }
    }
    private func save(_ room: SurveyRoom) -> Bool {
        guard var project = store.project(projectID), let i = project.rooms.firstIndex(where: { $0.id == roomID }) else { return false }
        project.rooms[i] = room
        return store.save(project)
    }
    private func saveOpening(_ opening: Opening) -> Bool {
        guard var latest = room else { return false }
        guard latest.openingProblem(opening, excluding: opening.id) == nil else { return false }
        if let i = latest.openings.firstIndex(where: { $0.id == opening.id }) { latest.openings[i] = opening }
        else { latest.openings.append(opening) }
        latest.measuredAt = Date()
        return save(latest)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
