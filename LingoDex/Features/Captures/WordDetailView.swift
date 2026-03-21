import SwiftUI
import UIKit
import Speech
import AVFoundation
import AudioToolbox

/// Detail view when user taps a capture card. Figma layout with 3D flip, TTS, inline pronunciation test.
struct WordDetailView: View {
    let deps: Dependencies
    @Bindable var viewModel: CapturesViewModel
    let initialWord: WordEntry
    let onDismiss: () -> Void

    private var displayedWord: WordEntry {
        viewModel.sessions.flatMap(\.words).first { $0.id == initialWord.id } ?? initialWord
    }

    @State private var image: UIImage?

    @State private var flipDegrees: Double = 90
    @State private var isSpeaking = false
    @State private var isSpeakerPulsing = false

    enum MicState: Equatable {
        case idle
        case recording
        case success
        case failure
    }

    @State private var micState: MicState = .idle
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

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
        .task(id: displayedWord.imageFileName) {
            do {
                image = try await deps.imageLoader.loadFullImage(fileName: displayedWord.imageFileName)
            } catch {
                image = nil
            }
        }
        .onAppear {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                flipDegrees = 0
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
                .rotation3DEffect(.degrees(flipDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.5)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260, maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(24)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundStyle(DesignTokens.colors.capturesTextSecondary.opacity(0.5))
                    )
                    .frame(width: 260, height: 280)
                    .padding(24)
            }
        }
    }

    private var wordLabels: some View {
        VStack(spacing: 16) {
            Text(displayedWord.learnWord)
                .font(CaptureTypography.detailWordTitle())
                .foregroundStyle(DesignTokens.colors.capturesTextPrimary)
                .multilineTextAlignment(.center)

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
            }
            .buttonStyle(.plain)
            .disabled(isSpeaking)

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
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            flipDegrees = 90
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            stopListening()
            onDismiss()
        }
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
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    isSpeakerPulsing = true
                }
            }
            do {
                try await deps.tts.speak(displayedWord.learnWord, language: .english)
            } catch { /* TTS error ignored for UX */ }
            await MainActor.run {
                isSpeakerPulsing = false
                isSpeaking = false
            }
        }
    }

    private func startRecording() {
        guard micState == .idle else { return }
        micState = .recording

        Task {
            let granted = await requestPermissions()
            guard granted else {
                await MainActor.run { micState = .idle }
                return
            }
            await MainActor.run {
                beginListening()
            }
        }
    }

    private func requestPermissions() async -> Bool {
        let speechOk = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                c.resume(returning: status == .authorized)
            }
        }
        guard speechOk else { return false }
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) }
        }
    }

    private func beginListening() {
        stopListening()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [request] buffer, _ in
            request.append(buffer)
        }

        let expectedWord = displayedWord.learnWord
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { result, error in
            Task { @MainActor in
                if let result, result.isFinal {
                    let transcript = result.bestTranscription.formattedString
                    let accuracy = Self.pronunciationAccuracy(expected: expectedWord, transcript: transcript)
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
                    stopListening()
                } else if error != nil {
                    micState = .idle
                    stopListening()
                }
            }
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            try audioEngine.start()
        } catch {
            micState = .idle
        }
    }

    private func stopRecording() {
        guard micState == .recording else { return }
        recognitionRequest?.endAudio()
    }

    private func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
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
