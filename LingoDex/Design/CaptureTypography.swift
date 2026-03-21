import SwiftUI
import UIKit

/// Typography aligned with Figma (Space Mono Regular). Add SpaceMono-Regular.ttf to the target for an exact match.
enum CaptureTypography {
    private static func spaceMono(size: CGFloat) -> Font {
        if UIFont(name: "SpaceMono-Regular", size: size) != nil {
            return .custom("SpaceMono-Regular", size: size)
        }
        return .system(size: size, weight: .regular, design: .monospaced)
    }

    static func dateTitle() -> Font { spaceMono(size: 21) }
    static func captureCount() -> Font { spaceMono(size: 14) }
    static func wordLabel() -> Font { spaceMono(size: 16) }
    static func detailWordTitle() -> Font { spaceMono(size: 24) }
    static func detailPhonetic() -> Font { spaceMono(size: 16) }
}
