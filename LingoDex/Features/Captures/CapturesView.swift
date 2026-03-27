import SwiftUI
import UIKit

struct CapturesView: View {
    private let deps: Dependencies
    private let appViewModel: AppViewModel
    @Bindable var capturesViewModel: CapturesViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var searchText: String = ""
    @State private var isShowingSortOptions = false
    @State private var sortOrder: SessionSortOrder = .mostRecent
    @State private var selectedWord: WordEntry?

    init(deps: Dependencies, appViewModel: AppViewModel, capturesViewModel: CapturesViewModel) {
        self.deps = deps
        self.appViewModel = appViewModel
        self.capturesViewModel = capturesViewModel
    }

    var body: some View {
        if appViewModel.authUser == nil {
            lockedState
        } else {
            NavigationStack {
                ZStack {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DesignTokens.layout.capturesSectionSpacing) {
                            content
                        }
                    .padding(.horizontal, DesignTokens.layout.capturesHorizontalPadding)
                    .padding(.top, 4)
                    .padding(.bottom, 100)
                }
                .safeAreaPadding(.top, 8)

                    if capturesViewModel.isProcessingCapture {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        ProgressView("Processing...")
                            .padding(14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .navigationTitle("Captures")
                .navigationBarTitleDisplayMode(.large)
                .searchable(text: $searchText, prompt: "Search words")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isShowingSortOptions = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityLabel("Sort order")
                    }
                }
            }
            .confirmationDialog("Sort captures", isPresented: $isShowingSortOptions, titleVisibility: .visible) {
                Button(SessionSortOrder.mostRecent.title) { sortOrder = .mostRecent }
                Button(SessionSortOrder.leastRecent.title) { sortOrder = .leastRecent }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(
                isPresented: Binding(
                    get: { capturesViewModel.isStorySheetPresented },
                    set: { capturesViewModel.isStorySheetPresented = $0 }
                )
            ) {
                StoryBottomSheet(deps: deps, viewModel: capturesViewModel)
            }
            .fullScreenCover(item: $selectedWord) { word in
                WordDetailView(
                    deps: deps,
                    viewModel: capturesViewModel,
                    initialWord: word,
                    onDismiss: { selectedWord = nil }
                )
            }
            .onChange(of: capturesViewModel.sessions) { _, sessions in
                let missingIDs = sessions
                    .flatMap(\.words)
                    .filter { $0.thumbnailData == nil }
                    .map(\.id)
                capturesViewModel.scheduleThumbnailBackfill(for: missingIDs)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if filteredSessions.isEmpty {
            emptyState
        } else {
            ForEach(sortedSessions) { session in
                sessionSection(session)
            }
        }
    }

    private var lockedState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Captures")
                .font(CaptureTypography.dateTitle())
                .foregroundStyle(DesignTokens.colors.capturesTextPrimary)

            Text("Sign in to start capturing objects and building your Pokédex.")
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
        .padding(.horizontal, DesignTokens.layout.capturesHorizontalPadding)
        .padding(.top, 20)
        .padding(.bottom, 100)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(capturesViewModel.sessions.isEmpty ? "No captures yet" : "No matches")
                .font(CaptureTypography.wordLabel())
                .foregroundStyle(DesignTokens.colors.capturesTextPrimary)
            Text(capturesViewModel.sessions.isEmpty ? "Use the camera button below to add a word." : "Try a different search.")
                .font(CaptureTypography.captureCount())
                .foregroundStyle(DesignTokens.colors.capturesTextSecondary)
        }
        .padding(DesignTokens.layout.capturesCardInnerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.layout.capturesCardCornerRadius, style: .continuous))
    }

    private func sessionSection(_ session: CaptureSession) -> some View {
        let title = session.date.formatted(.dateTime.month(.wide).day())
        return VStack(alignment: .leading, spacing: DesignTokens.layout.capturesDateSectionSpacing) {
            VStack(alignment: .leading, spacing: DesignTokens.layout.capturesDateSectionSpacing) {
                Text(title)
                    .font(CaptureTypography.dateTitle())
                    .foregroundStyle(DesignTokens.colors.capturesTextPrimary)
                Text("\(session.words.count) captures")
                    .font(CaptureTypography.captureCount())
                    .foregroundStyle(DesignTokens.colors.capturesTextSecondary)
            }

            VStack(alignment: .leading, spacing: 0) {
                LazyVGrid(
                    columns: captureGridColumns,
                    spacing: DesignTokens.layout.capturesGridSpacing
                ) {
                    ForEach(session.words) { word in
                        WordCard(word: word) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedWord = word
                        }
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.95).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: session.words.count)
            }
            .padding(DesignTokens.layout.capturesCardInnerPadding)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.layout.capturesCardCornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        }
    }

    /// Figma uses 2 columns on phone; more columns on regular width (iPad).
    private var captureGridColumns: [GridItem] {
        let spacing = DesignTokens.layout.capturesGridSpacing
        if horizontalSizeClass == .regular {
            return Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3)
        }
        return [
            GridItem(.flexible(), spacing: spacing),
            GridItem(.flexible(), spacing: spacing),
        ]
    }

    private var sortedSessions: [CaptureSession] {
        let base = filteredSessions
        switch sortOrder {
        case .mostRecent:
            return base.sorted { $0.date > $1.date }
        case .leastRecent:
            return base.sorted { $0.date < $1.date }
        }
    }

    private var filteredSessions: [CaptureSession] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return capturesViewModel.sessions.compactMap { session in
            let filteredWords: [WordEntry]
            if query.isEmpty {
                filteredWords = session.words
            } else {
                filteredWords = session.words.filter { matchesFuzzySearch($0, query: query) }
            }
            guard !filteredWords.isEmpty else { return nil }
            return CaptureSession(id: session.id, date: session.date, words: filteredWords)
        }
    }
}

private enum SessionSortOrder: Hashable {
    case mostRecent
    case leastRecent

    var title: String {
        switch self {
        case .mostRecent: "Most recent first"
        case .leastRecent: "Least recent first"
        }
    }
}

/// Substring + tokenized fuzzy match across learn, native, and recognized English.
private func matchesFuzzySearch(_ word: WordEntry, query: String) -> Bool {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if q.isEmpty { return true }
    let blob = "\(word.learnWord) \(word.nativeWord) \(word.recognizedEnglish)".lowercased()
    if blob.contains(q) { return true }
    let tokens = q.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard !tokens.isEmpty else { return true }
    return tokens.allSatisfy { token in blob.contains(token) }
}

/// Figma-style cell: transparent cutout image, term below — no border, no chrome.
private struct WordCard: View {
    let word: WordEntry
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                ZStack {
                    Color.clear
                    Group {
                        if let thumbnailData = word.thumbnailData, let uiImage = UIImage(data: thumbnailData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .renderingMode(.original)
                                .scaledToFit()
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 28, weight: .regular))
                                .foregroundStyle(DesignTokens.colors.capturesTextSecondary.opacity(0.5))
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)

                Text(word.learnWord)
                    .font(CaptureTypography.wordLabel())
                    .foregroundStyle(DesignTokens.colors.capturesLabel)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
