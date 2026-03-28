import SwiftUI
import UIKit

/// "Magic" lift + shimmer animation for sticker reveal, mimicking VisionKit's subject lift feel.
struct MagicLiftView: View {
    let image: UIImage
    @State private var shimmerOffset: CGFloat = -1.0
    @State private var isLifted: Bool = false

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(isLifted ? 1.05 : 1.0)
                .offset(y: isLifted ? -8 : 0)
                .shadow(color: DesignTokens.colors.magicLiftGlow.opacity(isLifted ? 0.8 : 0), radius: 25, x: 0, y: 0)
                .overlay(shimmerOverlay)
        }
        .compositingGroup()
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                isLifted = true
            }
            withAnimation(.linear(duration: 1.2).delay(0.2)) {
                shimmerOffset = 1.0
            }
        }
    }

    private var shimmerOverlay: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    .clear,
                    .white.opacity(0.05),
                    .white.opacity(0.5),
                    .white.opacity(0.05),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.35)
            .offset(x: shimmerOffset * geo.size.width * 1.5)
            .mask(
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            )
        }
    }
}
