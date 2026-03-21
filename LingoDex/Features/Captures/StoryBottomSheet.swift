import SwiftUI
import Observation

struct StoryBottomSheet: View {
    let deps: Dependencies
    @Bindable var viewModel: CapturesViewModel

    @State private var saveStatus: String?
    @State private var isSpeakingWord = false

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(Color.black.opacity(0.12))
                .frame(width: 54, height: 6)
                .padding(.top, 8)

            if viewModel.generatedStory == nil {
                if viewModel.isStoryGenerating {
                    generatingState
                } else {
                    readyState
                }
            } else if let story = viewModel.generatedStory {
                storyState(story)
            }

            if let saveStatus {
                Text(saveStatus)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }

    private var readyState: some View {
        VStack(spacing: 10) {
            Text("Ready for Story Time! 📖")
                .font(.system(size: 18, weight: .bold))
                .multilineTextAlignment(.center)

            Button {
                Task { await viewModel.createStoryIfNeeded() }
            } label: {
                Text("Create your story")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.colors.primary)
        }
        .padding(.top, 12)
    }

    private var generatingState: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Creating your story...")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private func storyState(_ story: Story) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(story.title)
                .font(.system(size: 20, weight: .bold, design: .monospaced))

            Text(story.body)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("Words")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 90), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(viewModel.storyTriggerWords) { entry in
                        Button {
                            Task {
                                isSpeakingWord = true
                                defer { isSpeakingWord = false }
                                try? await deps.tts.speak(entry.learnWord, language: .currentLearning)
                            }
                        } label: {
                            Text(entry.learnWord)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(DesignTokens.colors.primary.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isSpeakingWord)
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.saveGeneratedStory()
                    saveStatus = "Saved to My Stories (local)."
                } label: {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.colors.primary)

                Button {
                    saveStatus = "Share coming soon."
                } label: {
                    Text("Share")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 12)
    }
}
