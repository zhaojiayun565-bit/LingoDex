import SwiftUI
import UIKit

/// Sticker “lift” with breathing glow and float, driven by the parent reveal timeline plus continuous motion.
struct MagicLiftView: View {
    let image: UIImage
    /// Overall reveal progress 0...1 from `KeyframeAnimator`.
    var magicProgress: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            let date = context.date.timeIntervalSinceReferenceDate
            let breath = sin(date * 2.4) * 0.5 + 0.5
            let float = sin(date * 2.1) * 2.5

            let lift = smoothstep(magicProgress, 0, 0.42)
            let scale = 1.0 + 0.05 * lift + 0.018 * breath
            let yOffset = -8 * lift + float
            let glow = 0.55 + 0.45 * breath

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .background {
                    AngularGradient(
                        colors: [
                            DesignTokens.colors.primary.opacity(0.14),
                            DesignTokens.colors.stickerGlow.opacity(0.55),
                            DesignTokens.colors.primary.opacity(0.1),
                            DesignTokens.colors.stickerGlow.opacity(0.45)
                        ],
                        center: .center
                    )
                    .blur(radius: 14 + 8 * breath)
                    .opacity(0.75 * Double(lift) + 0.2)
                }
                .scaleEffect(scale)
                .offset(y: yOffset)
                .shadow(color: DesignTokens.colors.stickerGlow.opacity(glow), radius: 16 + 10 * breath, x: 0, y: 8)
                .shadow(color: DesignTokens.colors.primary.opacity(0.32 * glow), radius: 26 + 12 * breath, x: 0, y: 12)
                .shadow(color: Color.black.opacity(0.08 * lift), radius: 12, x: 0, y: 8)
        }
    }

    /// Smooth 0...1 ramp between edges.
    private func smoothstep(_ x: CGFloat, _ edge0: CGFloat, _ edge1: CGFloat) -> CGFloat {
        guard edge1 > edge0 else { return x >= edge1 ? 1 : 0 }
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}
