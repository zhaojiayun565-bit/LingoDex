import Foundation
import SwiftUI

struct SpeechVerifySheet: View {
    let expectedWord: String
    let nativeHint: String
    let language: Language

    @Environment(\.dismiss) private var dismiss

    @State private var speech = SpeechSessionController()

    @State private var isCorrect: Bool? = nil

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

                WaveformView(bars: speech.waveform)
                    .frame(height: 80)

                if let isCorrect {
                    verdict
                }

                if let errorMessage = speech.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                } else {
                    VStack(spacing: 6) {
                        Text("You said:")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text(speech.transcript.isEmpty ? "—" : speech.transcript)
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
                        speech.stopByUser()
                        dismiss()
                    }
                }
            }
            .onAppear {
                if speech.transcript.isEmpty && !speech.isListening {
                    Task { await requestAndStart() }
                }
            }
            .onDisappear {
                speech.stopByUser()
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
            if speech.isListening {
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
        isCorrect = nil
        speech.clearDisplayState()
    }

    private func requestAndStart() async {
        let granted = await speech.requestPermissions()
        guard granted else {
            speech.errorMessage = "Permissions are required for recording and speech recognition."
            return
        }
        await MainActor.run {
            speech.start(language: language, shouldReportPartialResults: true) { transcript in
                isCorrect = comparePronunciation(transcript: transcript, expected: expectedWord)
            }
        }
    }

    private func stopAndFinalize() {
        guard speech.isListening else { return }
        speech.stopAndFinalize()
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

