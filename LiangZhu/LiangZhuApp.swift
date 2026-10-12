import SwiftUI

@main
struct LiangZhuApp: App {
    @StateObject private var store = ProjectStore()
    var body: some Scene {
        WindowGroup {
            DashboardView().environmentObject(store).tint(Palette.green)
                .preferredColorScheme(.light)
                .alert("本地存储提示", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                    Button("知道了", role: .cancel) { store.errorMessage = nil }
                } message: { Text(store.errorMessage ?? "") }
        }
    }
}
