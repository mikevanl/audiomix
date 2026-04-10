import SwiftUI

struct LevelMeterView: View {
    let level: Float32

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.primary.opacity(0.08))

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(levelColor)
                    .frame(width: max(0, geo.size.width * CGFloat(level)))
            }
        }
        .frame(height: 3)
    }

    private var levelColor: Color {
        if level > 0.9 { return .red }
        if level > 0.7 { return .orange }
        return .green
    }
}
