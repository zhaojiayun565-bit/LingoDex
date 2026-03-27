import SwiftUI
import UIKit

struct PracticeView: View {
    private let deps: Dependencies
    private let appViewModel: AppViewModel
    @Bindable var viewModel: PracticeViewModel

    init(deps: Dependencies, appViewModel: AppViewModel, viewModel: PracticeViewModel) {
        self.deps = deps
        self.appViewModel = appViewModel
        self.viewModel = viewModel
    }

    var body: some View {
        if appViewModel.authUser == nil {
            lockedState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Practice")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))

                    if viewModel.dueWords.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(viewModel.dueWords.prefix(30))) { word in
                            PracticeCard(word: word) { rating in
                                viewModel.rate(wordId: word.id, rating: rating)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 92)
            }
            .onChange(of: viewModel.dueWords) { _, dueWords in
                let missingIDs = dueWords.filter { $0.thumbnailData == nil }.map(\.id)
                viewModel.scheduleThumbnailBackfill(for: missingIDs)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No cards due")
                .font(.system(size: 18, weight: .semibold))
            Text("Your next review will appear here automatically.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DesignTokens.colors.cardStroke, lineWidth: 1)
        )
    }

    private var lockedState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Practice")
                .font(.system(size: 28, weight: .bold, design: .monospaced))

            Text("Sign in to unlock spaced repetition practice.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Button {
                appViewModel.selectedTab = .me
            } label: {
                Text("Go to Sign In")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.colors.primary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 92)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PracticeCard: View {
    let word: WordEntry
    let onRate: (SRSRating) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(DesignTokens.colors.cardStroke, lineWidth: 1)
                    )
                    .frame(height: 150)

                if let thumbnailData = word.thumbnailData, let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .frame(height: 150)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(DesignTokens.colors.primary.opacity(0.9))
                        )
                }

                if let due = word.srs.nextDueDate {
                    Text("Due \(due.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Capsule())
                        .padding(12)
                }
            }

            Text(word.learnWord)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .lineLimit(2)

            Text(word.nativeWord)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 10) {
                Text("How was it?")
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: 10) {
                    ratingButton("Again", .again)
                    ratingButton("Hard", .hard)
                }
                HStack(spacing: 10) {
                    ratingButton("Good", .good)
                    ratingButton("Easy", .easy)
                }
            }
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DesignTokens.colors.cardStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func ratingButton(_ title: String, _ rating: SRSRating) -> some View {
        Button {
            onRate(rating)
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(DesignTokens.colors.primary)
        .accessibilityLabel(title)
    }
}

