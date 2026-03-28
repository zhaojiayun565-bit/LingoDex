import SwiftUI
import UIKit
import AVFoundation

/// Post-capture result: extracted object, translation, TTS, mic, Save/Cancel. Layout matches WordDetailView.
struct StickerResultView: View {
    let word: WordEntry
    let extractedImage: UIImage
    let deps: Dependencies
    let onSave: () -> Void
    let onDismiss: () -> Void
    let onRetry: () -> Void
    let onTryPronunciation: (WordEntry) -> Void

    @State private var isSaving = false
    @State private var isSpeaking = false
    @State private var isSpeakerPulsing = false
    @State private var appearScale: CGFloat = 0.92
    @State private var appearOpacity: Double = 0

    var body: some View {
        ZStack {
            DesignTokens.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 24)
                mainCard
                    .scaleEffect(isSaving ? 0.6 : appearScale)
                    .opacity(isSaving ? 0 : appearOpacity)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appearScale)
                    .animation(.easeOut(duration: 0.35), value: isSaving)
                Spacer(minLength: 40)
                actionButtons
                Spacer(minLength: 24)
                SaveCancelButtons(
                    onSave: saveAndAnimate,
                    onCancel: nil,
                    isSaveDisabled: isSaving
                )
                .padding(.horizontal, 20)
                Spacer(minLength: 60)
            }
        }
        .onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try? AVAudioSession.sharedInstance().setActive(true)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                appearScale = 1.0
                appearOpacity = 1
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onRetry()
            } label: {
                Image(systemName: "arrow.clockwise")
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
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
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
        VStack(spacing: -16) { // Pulls the text up into the sticker
            MagicLiftView(image: extractedImage)
                .frame(maxWidth: 260, maxHeight: 280)
                .padding(.bottom, 16)

            // Wrap the labels in a sticker-like bubble
            VStack(spacing: 4) {
                Text(word.learnWord)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(isPending ? DesignTokens.colors.capturesTextSecondary : DesignTokens.colors.capturesTextPrimary)
                    .multilineTextAlignment(.center)

                if let phonetic = word.phoneticBreakdown, !phonetic.isEmpty {
                    Text(phonetic)
                        .font(CaptureTypography.detailPhonetic())
                        .foregroundStyle(DesignTokens.colors.primary)
                        .multilineTextAlignment(.center)
                }

                Text(word.nativeWord)
                    .font(CaptureTypography.detailPhonetic())
                    .foregroundStyle(DesignTokens.colors.capturesTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            .zIndex(1)
        }
    }

    private var isPending: Bool {
        word.learnWord == "Loading…" || word.learnWord == "Loading..."
    }

    private var actionButtons: some View {
        HStack(spacing: 40) {
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
                    .animation(isSpeaking ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .easeOut(duration: 0.25), value: isSpeakerPulsing)
            }
            .buttonStyle(.plain)
            .disabled(isSpeaking || isPending)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTryPronunciation(word)
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(DesignTokens.colors.capturesTextSecondary)
                    .frame(width: DesignTokens.layout.detailActionButtonSize, height: DesignTokens.layout.detailActionButtonSize)
                    .background(Color.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DesignTokens.colors.cardStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isPending)
        }
    }

    private func pronounce() {
        guard !isSpeaking else { return }
        isSpeaking = true
        isSpeakerPulsing = false

        Task {
            isSpeakerPulsing = true
            do {
                try await deps.tts.speak(word.learnWord, language: .currentLearning)
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
