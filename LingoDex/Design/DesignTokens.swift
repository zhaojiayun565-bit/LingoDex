import SwiftUI
import Foundation

enum DesignTokens {
    enum colors {
        static let primary = Color(hex: "#FF5A5F")
        static let background = Color(hex: "#FAFAFA")
        static let cardStroke = Color(hex: "#EEEEEE")
        static let stickerGlow = Color(hex: "#FF5A5F").opacity(0.25)
        /// Figma captures — primary text
        static let capturesTextPrimary = Color(hex: "#121212")
        /// Figma captures — secondary (counts)
        static let capturesTextSecondary = Color(hex: "#767676")
        /// Figma — word labels on cards
        static let capturesLabel = Color(hex: "#000000")
    }

    enum layout {
        static let stickerCornerRadius: CGFloat = 24
        static let stickerShadowRadius: CGFloat = 12
        /// Figma frame horizontal inset
        static let capturesHorizontalPadding: CGFloat = 20
        /// Section date ↔ count
        static let capturesDateSectionSpacing: CGFloat = 8
        /// Between date block and card
        static let capturesSectionSpacing: CGFloat = 16
        /// Card corner (Figma 20)
        static let capturesCardCornerRadius: CGFloat = 20
        /// Top bar icon buttons (Figma 40)
        static let capturesIconButtonSize: CGFloat = 40
        /// Gap between filter and search (Figma 8)
        static let capturesHeaderActionsGap: CGFloat = 8
        /// Inner card padding (Figma ~16 implied)
        static let capturesCardInnerPadding: CGFloat = 16
        /// 2-column grid spacing (Figma ~16)
        static let capturesGridSpacing: CGFloat = 16
        /// Detail view action buttons (volume, mic) — Figma 65
        static let detailActionButtonSize: CGFloat = 65
    }
}

private extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var value: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&value)

        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0

        self = Color(red: r, green: g, blue: b)
    }
}

