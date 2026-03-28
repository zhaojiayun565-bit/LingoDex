import SwiftUI

/// Subtle dot-grid paper texture (Canvas) for the card morph reveal.
struct DotGridBackground: View {
    var dotSpacing: CGFloat = 14
    var dotRadius: CGFloat = 0.75

    @Environment(\.colorScheme) private var colorScheme

    private var dotColor: Color {
        DesignTokens.colors.cardStroke.opacity(colorScheme == .dark ? 0.45 : 0.55)
    }

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / dotSpacing)) + 1
            let rows = Int(ceil(size.height / dotSpacing)) + 1

            for row in 0..<rows {
                for col in 0..<cols {
                    let x = CGFloat(col) * dotSpacing + dotSpacing * 0.5
                    let y = CGFloat(row) * dotSpacing + dotSpacing * 0.5
                    let rect = CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                }
            }
        }
        .ignoresSafeArea()
    }
}
