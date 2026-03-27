import SwiftUI

struct WorldView: View {
    private let deps: Dependencies
    @Bindable var viewModel: WorldViewModel

    init(deps: Dependencies, viewModel: WorldViewModel) {
        self.deps = deps
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("World")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
            Text("Social feed is planned post-MVP.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 92)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

