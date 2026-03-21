import SwiftUI

/// Reusable Save (primary) + optional Cancel (secondary) CTA. Matches profile edit name modal.
struct SaveCancelButtons: View {
    let onSave: () -> Void
    var onCancel: (() -> Void)? = nil
    var saveLabel: String = "Save"
    var cancelLabel: String = "Cancel"
    var isSaveDisabled: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onSave) {
                Text(saveLabel)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Color.black)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSaveDisabled)

            if let onCancel {
                Button(action: onCancel) {
                    Text(cancelLabel)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(DesignTokens.colors.capturesTextSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }
}
