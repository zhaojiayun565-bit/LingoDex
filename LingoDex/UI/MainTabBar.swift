import SwiftUI

struct MainTabBar: View {
    let selected: MainTab
    let onSelect: (MainTab) -> Void
    let onCenterCapture: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.captures, label: "Captures", icon: "square.grid.2x2.fill")
            tabButton(.practice, label: "Practice", icon: "waveform")
            centerCaptureButton
            tabButton(.world, label: "World", icon: "globe")
            tabButton(.me, label: "Me", icon: "person.fill")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 50, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.03), radius: 5, x: 0, y: 1)
        )
    }

    private var centerCaptureButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onCenterCapture()
        } label: {
            ZStack {
                Circle()
                    .fill(DesignTokens.colors.primary)
                    .frame(width: 52, height: 52)
                    .shadow(color: DesignTokens.colors.primary.opacity(0.35), radius: 8, x: 0, y: 4)
                Image(systemName: "camera.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .offset(y: -4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capture photo")
    }

    private func tabButton(_ tab: MainTab, label: String, icon: String) -> some View {
        let isSelected = selected == tab
        return Button {
            onSelect(tab)
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(DesignTokens.colors.primary)
                        .frame(height: 44)
                        .padding(.horizontal, 4)
                }

                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : DesignTokens.colors.primary.opacity(0.9))
                    Text(label)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(isSelected ? .white : DesignTokens.colors.primary.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
    }
}
