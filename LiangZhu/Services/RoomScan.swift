import SwiftUI
import RoomPlan
import AVFoundation
import simd

struct RoomScanView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = ScanController()
    var onSave: (SurveyRoom) -> Bool
    var body: some View {
        NavigationStack {
            Group {
                if !RoomCaptureSession.isSupported {
                    ContentUnavailableView("这台设备不支持 LiDAR 测绘", systemImage: "viewfinder", description: Text("请使用支持 RoomPlan 的 LiDAR 设备。\n也可以返回项目，选择手动记录房间。"))
                } else if controller.denied {
                    VStack(spacing: 20) {
                        ContentUnavailableView("需要相机权限", systemImage: "camera", description: Text("允许相机访问后，才能扫描房间墙面与门窗。"))
                        Button("打开系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    }
                } else if let error = controller.error {
                    ContentUnavailableView("扫描未完成", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if controller.authorized {
                    ZStack(alignment: .bottom) {
                        CaptureView(controller: controller).ignoresSafeArea(edges: .bottom)
                        VStack(spacing: 12) {
                            Text(controller.processing ? "正在生成房间轮廓…" : "缓慢移动设备，依次扫描每面墙和门窗")
                                .font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                            if controller.processing { ProgressView() }
                            else { PrimaryButton(title: "完成扫描", symbol: "checkmark") { controller.finish() } }
                        }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24)).padding(20)
                    }
                } else { ProgressView("准备相机…") }
            }.navigationTitle("扫描一个房间").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { controller.cancel(); dismiss() } } }
                .task {
                    controller.onResult = { room in if onSave(room) { dismiss() } else { controller.error = "扫描完成，但本地保存失败。请检查存储后重试。" } }
                    await controller.requestCamera()
                }.onDisappear { controller.cancel() }
        }.tint(Palette.green)
    }
}

private struct CaptureView: UIViewRepresentable {
    let controller: ScanController
    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        controller.attach(view)
        return view
    }
    func updateUIView(_ view: RoomCaptureView, context: Context) { }
    static func dismantleUIView(_ view: RoomCaptureView, coordinator: ()) { view.captureSession.stop() }
}

@MainActor
final class ScanController: NSObject, ObservableObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    @Published var authorized = false
    @Published var denied = false
    @Published var processing = false
    @Published var error: String?
    var onResult: ((SurveyRoom) -> Void)?
    private var captureView: RoomCaptureView?
    private var cancelled = false
    private var timeout: Task<Void, Never>?
    override init() { super.init() }
    nonisolated required init?(coder: NSCoder) { super.init() }
    nonisolated func encode(with coder: NSCoder) { }
    func requestCamera() async {
        guard RoomCaptureSession.isSupported else { return }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard !cancelled else { return }
        authorized = granted; denied = !granted
    }
    func attach(_ view: RoomCaptureView) {
        captureView = view; view.delegate = self; view.captureSession.delegate = self
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }
    func finish() {
        processing = true
        captureView?.captureSession.stop()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self, !self.cancelled else { return }
            self.error = "处理扫描超时，请返回后重新扫描。"
        }
    }
    func cancel() { cancelled = true; timeout?.cancel(); captureView?.captureSession.stop(); captureView?.delegate = nil; captureView?.captureSession.delegate = nil }
    nonisolated func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        guard let error else { return }
        Task { @MainActor [weak self] in
            guard let self, !self.cancelled else { return }
            self.timeout?.cancel(); self.error = error.localizedDescription
        }
    }
    nonisolated func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        if let error { Task { @MainActor [weak self] in self?.error = error.localizedDescription }; return false }
        return true
    }
    nonisolated func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, !self.cancelled else { return }
            self.timeout?.cancel()
            if let error { self.error = error.localizedDescription; return }
            do { self.onResult?(try ScanImporter.convert(processedResult)) }
            catch { self.error = error.localizedDescription }
        }
    }
}

enum ScanImporter {
    enum ImportError: LocalizedError {
        case incomplete, multipleFloors, curvedWalls
        var errorDescription: String? {
            switch self {
            case .incomplete: "没有识别到完整有效的地面轮廓，请重新扫描整个房间。"
            case .multipleFloors: "识别到多块地面。当前版本一次记录一个房间，请分开扫描或使用手动轮廓。"
            case .curvedWalls: "识别到弧形墙面。当前平面图只支持直线墙，请手动记录现场轮廓。"
            }
        }
    }
    static func convert(_ captured: CapturedRoom) throws -> SurveyRoom {
        guard !captured.walls.contains(where: { $0.curve != nil }) else { throw ImportError.curvedWalls }
        guard captured.floors.count <= 1 else { throw ImportError.multipleFloors }
        guard let floor = captured.floors.first, floor.polygonCorners.count >= 3 else { throw ImportError.incomplete }
        let world = floor.polygonCorners.map { floor.transform * SIMD4<Float>($0.x, $0.y, $0.z, 1) }
        let minX = world.map(\.x).min() ?? 0, minZ = world.map(\.z).min() ?? 0
        var points = world.map { PlanPoint(x: Double($0.x - minX), y: Double($0.z - minZ)) }
        if let first = points.first, let last = points.last, first.distance(to: last) < 0.001 { points.removeLast() }
        guard SurveyRoom.validPolygon(points) else { throw ImportError.incomplete }
        let heights = captured.walls.map { Double($0.dimensions.y) }.filter { $0 >= 1 && $0 <= 20 }.sorted()
        guard !heights.isEmpty else { throw ImportError.incomplete }
        var room = SurveyRoom(name: "扫描房间", vertices: points, height: heights[heights.count / 2], source: .lidar)
        var skipped = 0
        for (surfaces, kind) in [(captured.doors, OpeningKind.door), (captured.windows, .window), (captured.openings, .passage)] {
            for surface in surfaces {
                let p = PlanPoint(x: Double(surface.transform.columns.3.x - minX), y: Double(surface.transform.columns.3.z - minZ))
                let candidates = points.indices.map { i -> (Int, Double, Double) in
                    let a = points[i], b = points[(i + 1) % points.count], length = a.distance(to: b)
                    let t = ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / (length * length)
                    let clamped = min(1, max(0, t))
                    let projected = PlanPoint(x: a.x + clamped * (b.x - a.x), y: a.y + clamped * (b.y - a.y))
                    return (i, p.distance(to: projected), t * length)
                }
                guard let best = candidates.min(by: { $0.1 < $1.1 }), best.1 <= 0.35 else { skipped += 1; continue }
                let width = Double(surface.dimensions.x), height = Double(surface.dimensions.y)
                let rawOffset = best.2 - width / 2
                let wallLength = room.edgeLength(best.0)
                guard rawOffset >= -0.1, rawOffset + width <= wallLength + 0.1 else { skipped += 1; continue }
                let floorY = Double(world.map(\.y).reduce(0, +)) / Double(world.count)
                let sill = kind == .window ? max(0, Double(surface.transform.columns.3.y) - height / 2 - floorY) : 0
                let opening = Opening(kind: kind, edge: best.0, offset: max(0, min(rawOffset, wallLength - width)), width: width, height: height, sill: sill)
                guard room.openingProblem(opening) == nil else { skipped += 1; continue }
                room.openings.append(opening)
            }
        }
        room.notes = "LiDAR 估测数据，请复核关键施工尺寸。墙面按地面轮廓投影，图纸顶部为示意方向。"
        if skipped > 0 { room.notes += "\n有 \(skipped) 个门窗无法可靠匹配或尺寸不合法，未导入，请现场补录。" }
        return room
    }
}
