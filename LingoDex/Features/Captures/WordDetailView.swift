import SwiftUI
import UIKit
import AudioToolbox

/// Detail view when user taps a capture card. Figma layout, hero image match, swipe-to-dismiss, TTS, mic check.
struct WordDetailView: View {
    let deps: Dependencies
    @Bindable var viewModel: CapturesViewModel
    let initialWord: WordEntry
    let onDismiss: () -> Void
    /// When set, image animates from the grid card via `matchedGeometryEffect`.
    var heroNamespace: Namespace.ID? = nil

    private var displayedWord: WordEntry {
        viewModel.sessions.flatMap(\.words).first { $0.id == initialWord.id } ?? initialWord
    }

    private var isPendingRecognition: Bool {
        displayedWord.learnWord == "Loading…" || displayedWord.learnWord == "Loading..."
    }

    @State private var image: UIImage?
    @State private var dragOffset: CGSize = .zero

    @State private var isSpeaking = false
    @State private var isSpeakerPulsing = false

    enum MicState: Equatable {
        case idle
        case recording
        case success
        case failure
    }

    @State private var micState: MicState = .idle
    @State private var speech = SpeechSessionController()
    @State private var isAwaitingMicResult = false

    @State private var showOptionsMenu = false
    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false
    @State private var editLearnWord: String = ""
    @State private var editNativeWord: String = ""

    var body: some View {
        ZStack {
            DesignTokens.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 24)
                mainCard
                Spacer(minLength: 24)
                wordLabels
                Spacer(minLength: 40)
                actionButtons
                Spacer(minLength: 60)
            }
        }
        .offset(y: max(0, dragOffset.height))
        .scaleEffect(1.0 - (max(0, dragOffset.height) / 1000.0))
        .opacity(1.0 - (max(0, dragOffset.height) / 800.0))
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        speech.stopByUser()
                        onDismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .task(id: displayedWord.imageFileName) {
            do {
                image = try await deps.imageLoader.loadFullImage(fileName: displayedWord.imageFileName)
            } catch {
                image = nil
            }
        }
        .onAppear {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .onDisappear {
            speech.stopByUser()
        }
        .onChange(of: speech.errorMessage) { _, error in
            if error != nil && micState == .recording && isAwaitingMicResult {
                isAwaitingMicResult = false
                micState = .idle
            }
        }
        .confirmationDialog("Options", isPresented: $showOptionsMenu, titleVisibility: .visible) {
            Button("Edit") {
                editLearnWord = displayedWord.learnWord
                editNativeWord = displayedWord.nativeWord
                showEditSheet = true
            }
            Button("Delete", role: .destructive) {
                showDeleteConfirmation = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this word?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteWord(displayedWord) }
                dismissWithFlip()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .sheet(isPresented: $showEditSheet) {
            editSheet
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismissWithFlip()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DesignTokens.colors.capturesTextPrimary)
                    .frame(width: DesignTokens.layout.capturesIconButtonSize, height: DesignTokens.layout.capturesIconButtonSize)
                    .background(Color.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DesignTokens.colors.cardStroke, lineWidth: 1))
            }
            .padding(.leading, 20)
            .padding(.top, 32)

            Spacer()

            Button {
                showOptionsMenu = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DesignTokens.colors.capturesTextPrimary)
                    .frame(width: DesignTokens.layout.capturesIconButtonSize, height: DesignTokens.layout.capturesIconButtonSize)
                    .background(Color.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DesignTokens.colors.cardStroke, lineWidth: 1))
            }
            .padding(.trailing, 20)
            .padding(.top, 32)
        }
    }

    private var mainCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(DesignTokens.colors.cardStroke, lineWidth: 1)
                )
                .frame(width: 290, height: 349)

            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260, maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 48))
                                .foregroundStyle(DesignTokens.colors.capturesTextSecondary.opacity(0.5))
                        )
                        .frame(width: 260, height: 280)
                }
            }
            .padding(24)
            .applyHeroMatch(id: displayedWord.id, namespace: heroNamespace)
        }
    }

    private var wordLabels: some View {
        VStack(spacing: 16) {
            Text(displayedWord.learnWord)
                .font(CaptureTypography.detailWordTitle())
                .foregroundStyle(DesignTokens.colors.capturesTextPrimary)
                .multilineTextAlignment(.center)

            if let phonetic = displayedWord.phoneticBreakdown, !phonetic.isEmpty {
                Text(phonetic)
                    .font(CaptureTypography.detailPhonetic())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text(displayedWord.nativeWord)
                .font(CaptureTypography.detailPhonetic())
                .foregroundStyle(DesignTokens.colors.capturesTextSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 40) {
            // Volume — hear pronunciation
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                pronounce()
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(DesignTokens.colors.capturesTextSecondary)
                    .frame(width: DesignTokens.layout.detailActionButtonSize, height: DesignTokens.layout.detailActionButtonSize)
                    .background(Color.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DesignTokens.colors.cardStroke, lineWidth: 1))
                    .scaleEffect(isSpeakerPulsing ? 1.05 : 1.0)
                    .animation(isSpeaking ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true) : .easeOut(duration: 0.25), value: isSpeakerPulsing)
            }
            .buttonStyle(.plain)
            .disabled(isSpeaking || isPendingRecognition)

            // Mic — test pronunciation
            micButton
        }
    }

    @ViewBuilder
    private var micButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            switch micState {
            case .idle:
                startRecording()
            case .recording:
                stopRecording()
            case .success, .failure:
                micState = .idle
            }
        } label: {
            Group {
                switch micState {
                case .idle:
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(DesignTokens.colors.capturesTextSecondary)
                case .recording:
                    Image(systemName: "stop.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(DesignTokens.colors.primary)
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.green)
                case .failure:
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.red)
                }
            }
            .frame(width: DesignTokens.layout.detailActionButtonSize, height: DesignTokens.layout.detailActionButtonSize)
            .background(
                ZStack {
                    Circle()
                        .fill(micState == .recording ? DesignTokens.colors.primary.opacity(0.15) : Color.white)
                    if micState == .recording {
                        Circle()
                            .stroke(DesignTokens.colors.primary.opacity(0.5), lineWidth: 2)
                            .blur(radius: 4)
                    } else {
                        Circle().stroke(DesignTokens.colors.cardStroke, lineWidth: 1)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .disabled(isPendingRecognition)
    }

    private var editSheet: some View {
        NavigationStack {
            Form {
                TextField("Word", text: $editLearnWord)
                TextField("Translation", text: $editNativeWord)
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showEditSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        performEdit(learnWord: editLearnWord, nativeWord: editNativeWord)
                        showEditSheet = false
                    }
                }
            }
        }
    }

    private func dismissWithFlip() {
        speech.stopByUser()
        onDismiss()
    }

    private func performEdit(learnWord: String, nativeWord: String) {
        Task {
            await viewModel.updateWord(displayedWord, learnWord: learnWord, nativeWord: nativeWord)
        }
    }

    private func pronounce() {
        guard !isSpeaking else { return }
        isSpeaking = true
        isSpeakerPulsing = false

        Task {
            isSpeakerPulsing = true
            do {
                try await deps.tts.speak(displayedWord.learnWord, language: .currentLearning)
            } catch {
                // Surface TTS failures in Xcode console while debugging.
                print("🔊 Minimax TTS Error: \(error.localizedDescription)")
            }
            await MainActor.run {
                isSpeakerPulsing = false
                isSpeaking = false
            }
        }
    }

    private func startRecording() {
        guard micState == .idle else { return }
        micState = .recording
        isAwaitingMicResult = true

        Task {
            let granted = await speech.requestPermissions()
            guard granted else {
                await MainActor.run {
                    isAwaitingMicResult = false
                    micState = .idle
                }
                return
            }
            await MainActor.run {
                speech.start(language: .english, shouldReportPartialResults: false) { transcript in
                    isAwaitingMicResult = false
                    let accuracy = Self.pronunciationAccuracy(expected: displayedWord.learnWord, transcript: transcript)
                    if accuracy >= 0.6 {
                        micState = .success
                        AudioServicesPlaySystemSound(1057) // success ding
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            await MainActor.run {
                                if case .success = micState { micState = .idle }
                            }
                        }
                    } else {
                        micState = .failure
                    }
                }
            }
        }
    }

    private func stopRecording() {
        guard micState == .recording else { return }
        // Keep stop icon visible until final result callback sets success/failure.
        speech.stopAndFinalize()
    }

    /// Returns 0...1; 1 = perfect match.
    private static func pronunciationAccuracy(expected: String, transcript: String) -> Double {
        let norm = { (s: String) in
            s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined()
        }
        let e = norm(expected)
        let t = norm(transcript)
        guard !e.isEmpty else { return t.isEmpty ? 1 : 0 }
        if t.isEmpty { return 0 }

        let distance = levenshteinDistance(e, t)
        let maxLen = max(e.count, t.count)
        return 1.0 - Double(distance) / Double(maxLen)
    }

    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        var d = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
            }
        }
        return d[a.count][b.count]
    }
}

private extension View {
    @ViewBuilder
    func applyHeroMatch(id: UUID, namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}
