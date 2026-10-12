import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var creating = false
    @State private var showingGuide = false
    @State private var deleting: SurveyProject?
    @State private var importing = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("量筑").font(.system(size: 34, weight: .bold))
                            Text("把家的每一寸，记录清楚。")
                                .font(.subheadline).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Button { showingGuide = true } label: {
                            Image(systemName: "ruler").font(.title3).frame(width: 48, height: 48)
                                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        }.accessibilityLabel("测绘指南")
                    }
                    hero
                    HStack {
                        Text("我的测绘项目").font(.title3.bold())
                        Spacer()
                        Text("\(store.projects.count) 个项目").font(.caption).foregroundStyle(Palette.muted)
                    }
                    if store.projects.isEmpty {
                        ContentUnavailableView("从第一个房间开始", systemImage: "house", description: Text("新建项目，记录现场尺寸和门窗位置。"))
                    }
                    ForEach(store.projects.sorted { $0.updatedAt > $1.updatedAt }) { project in
                        NavigationLink(value: project.id) { ProjectCard(project: project) }.buttonStyle(.plain)
                            .contextMenu {
                                Button("删除项目", systemImage: "trash", role: .destructive) { deleting = project }
                            }
                    }
                    Label("数据保存在本机 · 支持导出 PDF 与备份", systemImage: "internaldrive")
                        .font(.caption).foregroundStyle(Palette.muted).padding(.bottom, 12)
                    Button("从 JSON 备份恢复项目", systemImage: "square.and.arrow.down") { importing = true }
                        .font(.subheadline).disabled(!store.canWrite)
                }.padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.background(Palette.background).foregroundStyle(Palette.ink)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: UUID.self) { ProjectDetailView(projectID: $0) }
                .sheet(isPresented: $creating) { ProjectEditor { project in store.save(project) } }
                .sheet(isPresented: $showingGuide) { GuideView() }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    switch result {
                    case .success(let url): _ = store.importBackup(url)
                    case .failure(let error): store.errorMessage = "导入失败：\(error.localizedDescription)"
                    }
                }
                .alert("删除项目？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("删除", role: .destructive) { if let deleting { store.delete(deleting.id) }; deleting = nil }
                    Button("取消", role: .cancel) { deleting = nil }
                } message: { Text("项目中的房间与测量记录将一并删除。") }
        }
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("现场测绘工作台", systemImage: "viewfinder").font(.caption.weight(.medium))
                Spacer()
                Text("ON SITE").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2)
            }.foregroundStyle(.white.opacity(0.7))
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("好装修\n始于准确测量").font(.system(size: 27, weight: .semibold)).lineSpacing(5)
                    Text("尺寸 · 门窗 · 现场备注").font(.caption).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
                Image(systemName: "square.dashed.inset.filled").font(.system(size: 63, weight: .ultraLight)).rotationEffect(.degrees(-10)).foregroundStyle(Color(red: 0.79, green: 0.85, blue: 0.67)).padding(.top, 6)
            }
            Button { creating = true } label: {
                HStack { Image(systemName: "plus"); Text("新建测绘项目"); Spacer(); Image(systemName: "arrow.up.right") }
                    .font(.subheadline.weight(.semibold)).padding(17)
                    .foregroundStyle(Palette.ink).background(Color(red: 0.87, green: 0.91, blue: 0.75), in: RoundedRectangle(cornerRadius: 14))
            }.disabled(!store.canWrite)
        }.padding(24).foregroundStyle(.white).background(Palette.ink, in: RoundedRectangle(cornerRadius: 26))
    }
}

struct ProjectCard: View {
    let project: SurveyProject
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "house.lodge").font(.title2).padding(12).background(Palette.background, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(project.name).font(.headline)
                        Text(project.address.isEmpty ? "尚未填写地址" : project.address).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                }
                HStack {
                    Metric(value: String(format: "%.2f", project.area), label: "净地面面积 m²")
                    Metric(value: "\(project.rooms.count)", label: "已记录房间")
                    VStack(alignment: .trailing, spacing: 7) {
                        Text(project.isExample ? "示例" : "本地已保存").font(.caption2.weight(.medium)).padding(.horizontal, 9).padding(.vertical, 5).background(Palette.background, in: Capsule())
                        Text(project.updatedAt, format: .dateTime.month().day()).font(.caption2).foregroundStyle(Palette.muted)
                    }
                }
            }
        }
    }
}

struct ProjectEditor: View {
    @Environment(\.dismiss) private var dismiss
    var existing: SurveyProject?
    var onSave: (SurveyProject) -> Bool
    @State private var name = ""
    @State private var address = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("项目信息") {
                    TextField("例如：阳光花园 1201", text: $name)
                    TextField("地址 / 楼栋 / 门牌号（选填）", text: $address)
                }
                Section { Text("每个项目可以记录多个房间。数据仅保存在此设备，请定期导出备份。")
                    .font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle(existing == nil ? "新建项目" : "编辑项目").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") {
                        var project = existing ?? SurveyProject(name: name)
                        project.name = name.trimmingCharacters(in: .whitespacesAndNewlines); project.address = address
                        if onSave(project) { dismiss() }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
                .onAppear { name = existing?.name ?? ""; address = existing?.address ?? "" }
        }.tint(Palette.green)
    }
}

struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("现场记录顺序") {
                    Label("1. 新建项目，填写地址", systemImage: "house")
                    Label("2. 量取墙面内净尺寸与层高", systemImage: "ruler")
                    Label("3. 按 W1、W2… 记录门窗位置", systemImage: "door.left.hand.open")
                    Label("4. 记录管井、梁柱和水电点位备注", systemImage: "square.and.pencil")
                    Label("5. 复核尺寸，导出 PDF 和 JSON 备份", systemImage: "square.and.arrow.up")
                }
                Section("尺寸与面积口径") {
                    Text("输入统一使用米。图纸可切换米 / 毫米。墙面按顶点顺序编号，门窗的距墙角距离沿该墙面起点计量。")
                    Text("净地面面积按房间轮廓计算；净墙面面积 = 周长 × 层高 − 门、窗、垭口面积。不含梁柱、踢脚线或材料损耗。")
                    Text("矩形和 L 形适合规则房间；不规则房间可逐点输入轮廓坐标。各房间图纸单独记录，尚不提供整屋拼接。")
                }
                Section("LiDAR 扫描") {
                    Text("扫描入口需要配备 LiDAR 且支持 RoomPlan 的设备，并允许相机访问。扫描尺寸为估测值，关键施工尺寸请现场复核。模拟器不能进行真实扫描。")
                }
            }.navigationTitle("测绘指南").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.tint(Palette.green)
    }
}
