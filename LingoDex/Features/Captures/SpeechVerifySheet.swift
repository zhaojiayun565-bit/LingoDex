import SwiftUI
import Speech
import AVFoundation

struct SpeechVerifySheet: View {
    let expectedWord: String
    let nativeHint: String
    let language: Language

    @Environment(\.dismiss) private var dismiss

    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()

    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?

    @State private var isListening = false
    @State private var transcript: String = ""
    @State private var isCorrect: Bool? = nil
    @State private var errorMessage: String?

    // Simple waveform bars.
    @State private var waveform: [CGFloat] = Array(repeating: 0.15, count: 24)

    init(expectedWord: String, nativeHint: String, language: Language) {
        self.expectedWord = expectedWord
        self.nativeHint = nativeHint
        self.language = language
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language.localeTag))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text(expectedWord)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                    Text("(\(nativeHint))")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                WaveformView(bars: waveform)
                    .frame(height: 80)

                if let isCorrect {
                    verdict
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                } else {
                    VStack(spacing: 6) {
                        Text("You said:")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text(transcript.isEmpty ? "—" : transcript)
                            .font(.system(size: 15))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 16)
                }

                Spacer()

                controls
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .navigationTitle("Try It")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        stopListening()
                        dismiss()
                    }
                }
            }
            .onAppear {
                if transcript.isEmpty && !isListening {
                    Task { await requestAndStart() }
                }
            }
        }
    }

    private var verdict: some View {
        let color: Color = (isCorrect ?? false) ? .green : .red
        let label = (isCorrect ?? false) ? "Correct" : "Try again"
        return Text(label)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if isListening {
                Button {
                    stopAndFinalize()
                } label: {
                    Text("Stop")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.colors.primary)
            } else {
                Button {
                    resetForRetry()
                    Task { await requestAndStart() }
                } label: {
                    Text("Record")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.colors.primary)
            }

            if isCorrect == false || isCorrect == true {
                Button {
                    resetForRetry()
                    Task { await requestAndStart() }
                } label: {
                    Text("Try Again")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func resetForRetry() {
        transcript = ""
        isCorrect = nil
        errorMessage = nil
        waveform = Array(repeating: 0.15, count: 24)
    }

    private func requestAndStart() async {
        guard let speechRecognizer else {
            errorMessage = "Speech recognition is not available on this device."
            return
        }

        do {
            let granted = try await requestMicrophoneAndSpeechPermissions()
            guard granted else {
                errorMessage = "Permissions are required for recording and speech recognition."
                return
            }
            startListening()
        } catch {
            errorMessage = "Could not start recording."
        }
    }

    private func requestMicrophoneAndSpeechPermissions() async throws -> Bool {
        let speechAuth = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        guard speechAuth else { return false }

        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    private func startListening() {
        if isListening { return }

        // Reset any previous task state.
        stopListening()

        isCorrect = nil
        transcript = ""
        errorMessage = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        // `inputNode` is non-optional; it is always available once the audio engine exists.
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            updateWaveform(with: buffer)
            self.recognitionRequest?.append(buffer)
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { result, error in
            DispatchQueue.main.async {
                if let result {
                    transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        isListening = false
                        isCorrect = comparePronunciation(transcript: transcript, expected: expectedWord)
                        stopListening()
                    }
                } else if let error {
                    isListening = false
                    self.errorMessage = error.localizedDescription
                    stopListening()
                }
            }
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            try audioEngine.start()
            isListening = true
        } catch {
            errorMessage = "Audio engine could not start."
            isListening = false
        }
    }

    private func stopAndFinalize() {
        guard isListening else { return }

        isListening = false
        recognitionRequest?.endAudio()
        stopListening()
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

    private func updateWaveform(with buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let channelDataArray = UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength))
        var sumSquares: Float = 0
        for sample in channelDataArray {
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(buffer.frameLength))

        // Map RMS into a visual range.
        let level = min(max(rms * 12, 0.05), 1.0)

        DispatchQueue.main.async {
            let count = waveform.count
            for i in 0..<count {
                let jitter = CGFloat.random(in: -0.08...0.08)
                let target = max(0.12, min(1.0, CGFloat(level) + jitter))
                waveform[i] = max(waveform[i] * 0.85, target)
            }
        }
    }

    private func comparePronunciation(transcript: String, expected: String) -> Bool {
        let normalize: (String) -> String = { text in
            text
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined()
        }

        let t = normalize(transcript)
        let e = normalize(expected)

        guard !t.isEmpty, !e.isEmpty else { return false }
        return t.contains(e) || e.contains(t)
    }
}

private struct WaveformView: View {
    let bars: [CGFloat]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(bars.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(DesignTokens.colors.primary.opacity(0.75))
                    .frame(width: 3, height: max(4, bars[i] * 60))
            }
        }
        .animation(.easeOut(duration: 0.05), value: bars)
    }
}

