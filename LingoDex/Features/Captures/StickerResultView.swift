import SwiftUI
import UIKit

/// Sticker-style result card: extracted object, translation text, and actions (TTS, mic, Save).
struct StickerResultView: View {
    let word: WordEntry
    let extractedImage: UIImage
    let deps: Dependencies
    let onSave: () -> Void
    let onDismiss: () -> Void
    let onTryPronunciation: (WordEntry) -> Void

    @State private var isSaving = false
    @State private var isSpeaking = false
    @State private var isSpeakerPulsing = false
    @State private var appearScale: CGFloat = 0.92
    @State private var appearOpacity: Double = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
            // Sticker card: object + text
            stickerCard
                .scaleEffect(isSaving ? 0.6 : appearScale)
                .opacity(isSaving ? 0 : appearOpacity)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appearScale)
                .animation(.easeOut(duration: 0.35), value: isSaving)

            // Action row: sound, mic, Save
            actionRow
        }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.colors.background.ignoresSafeArea())
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onDismiss()
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                appearScale = 1.0
                appearOpacity = 1
            }
        }
    }

    private var stickerCard: some View {
        VStack(spacing: 16) {
            // Object area with soft shadow/glow
            ZStack {
                Image(uiImage: extractedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .shadow(color: DesignTokens.colors.stickerGlow, radius: DesignTokens.layout.stickerShadowRadius)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)

            // Text block
            VStack(spacing: 4) {
                Text(word.learnWord)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(word.nativeWord)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.layout.stickerCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.layout.stickerCornerRadius, style: .continuous)
                .stroke(DesignTokens.colors.cardStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }

    private var actionRow: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                // Sound (TTS)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    pronounce()
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(DesignTokens.colors.primary))
                        .scaleEffect(isSpeakerPulsing ? 1.08 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(isSpeaking)

                // Mic (pronunciation check)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onTryPronunciation(word)
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(DesignTokens.colors.primary)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(DesignTokens.colors.primary.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                saveAndAnimate()
            } label: {
                Text("Save to captures")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.colors.primary)
            .disabled(isSaving)
        }
    }

    private func pronounce() {
        guard !isSpeaking else { return }
        isSpeaking = true
        isSpeakerPulsing = false

        Task {
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    isSpeakerPulsing = true
                }
            }
            do {
                try await deps.tts.speak(word.learnWord, language: .english)
            } catch { /* ignore */ }
            await MainActor.run {
                isSpeakerPulsing = false
                isSpeaking = false
            }
        }
    }

    private func saveAndAnimate() {
        guard !isSaving else { return }
        isSaving = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onSave()
        }
    }
}
