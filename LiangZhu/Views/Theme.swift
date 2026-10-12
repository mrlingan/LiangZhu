import SwiftUI

enum Palette {
    static let background = Color(red: 0.96, green: 0.96, blue: 0.93)
    static let ink = Color(red: 0.13, green: 0.24, blue: 0.22)
    static let green = Color(red: 0.20, green: 0.37, blue: 0.31)
    static let orange = Color(red: 0.83, green: 0.39, blue: 0.22)
    static let muted = Color(red: 0.43, green: 0.48, blue: 0.45)
    static let line = Color(red: 0.85, green: 0.88, blue: 0.83)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct Metric: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PrimaryButton: View {
    let title: String
    let symbol: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17)
                .foregroundStyle(.white).background(Palette.green, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
}
