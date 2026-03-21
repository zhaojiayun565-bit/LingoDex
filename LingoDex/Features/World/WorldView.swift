import SwiftUI

struct WorldView: View {
    private let deps: Dependencies
    @State private var viewModel: WorldViewModel

    init(deps: Dependencies) {
        self.deps = deps
        _viewModel = State(initialValue: WorldViewModel(deps: deps))
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

