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
    @Namespace private var heroAnimation

    init(deps: Dependencies, appViewModel: AppViewModel, capturesViewModel: CapturesViewModel) {
        self.deps = deps
        self.appViewModel = appViewModel
        self.capturesViewModel = capturesViewModel
    }

    var body: some View {
        if appViewModel.authUser == nil {
            lockedState
        } else {
            ZStack {
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

                if let word = selectedWord {
                    WordDetailView(
                        deps: deps,
                        viewModel: capturesViewModel,
                        initialWord: word,
                        onDismiss: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                selectedWord = nil
                            }
                        },
                        heroNamespace: heroAnimation
                    )
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: selectedWord?.id)
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
                        WordCard(word: word, heroNamespace: heroAnimation) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                selectedWord = word
                            }
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

private struct WordCard: View {
    let word: WordEntry
    var heroNamespace: Namespace.ID
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            // Use negative spacing to pull the text bubble slightly over the image
            VStack(spacing: -12) {
                Group {
                    if let thumbnailData = word.thumbnailData, let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .renderingMode(.original)
                            .scaledToFit()
                            // Fakes a white sticker outline by layering shadows
                            .shadow(color: .white, radius: 1, x: 1, y: 1)
                            .shadow(color: .white, radius: 1, x: -1, y: -1)
                            .shadow(color: .white, radius: 1, x: 1, y: -1)
                            .shadow(color: .white, radius: 1, x: -1, y: 1)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundStyle(DesignTokens.colors.capturesTextSecondary.opacity(0.5))
                            .frame(height: 100)
                    }
                }
                .matchedGeometryEffect(id: word.id, in: heroNamespace)
                .frame(maxWidth: .infinity)
                .frame(height: 110) // Give it a fixed height instead of a 1:1 ratio

                // The text label acting as the bottom of the sticker
                Text(word.learnWord)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.colors.capturesTextPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .zIndex(1) // Ensures the text sits on top of the image
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
