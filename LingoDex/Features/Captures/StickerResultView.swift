import SwiftUI
import UIKit
import AVFoundation

/// Post-capture result: extracted object, translation, TTS, mic, Save/Cancel — with magical reveal sequencing.
struct StickerResultView: View {
    let word: WordEntry
    let extractedImage: UIImage
    let capturedImageInfo: CapturedImageInfo?
    let deps: Dependencies
    let onSave: () -> Void
    let onDismiss: () -> Void
    let onRetry: () -> Void
    let onTryPronunciation: (WordEntry) -> Void

    @State private var isSaving = false
    @State private var isSpeaking = false
    @State private var isSpeakerPulsing = false
    @State private var playReveal = 0

    var body: some View {
        ZStack {
            DesignTokens.colors.background.ignoresSafeArea()

            KeyframeAnimator(initialValue: CGFloat(0), trigger: playReveal) { timeline in
                revealedLayout(timeline: timeline)
            } keyframes: { _ in
                KeyframeTrack(\.self) {
                    CubicKeyframe(0, duration: 0.02)
                    CubicKeyframe(1, duration: 2.05)
                }
            }
        }
        .onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try? AVAudioSession.sharedInstance().setActive(true)
            playReveal += 1
        }
    }

    @ViewBuilder
    private func revealedLayout(timeline t: CGFloat) -> some View {
        let dissolve = min(1, max(0, t / 0.72))
        let showBottomChrome = t >= 0.74

        ZStack {
            if let capture = capturedImageInfo {
                Image(uiImage: capture.image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .layerEffect(
                        ShaderLibrary.pixelateDissolve(.float(dissolve)),
                        maxSampleOffset: CGSize(width: 64, height: 64)
                    )
            }

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 24)
                PhaseAnimator([CGFloat(0.97), CGFloat(1.0)], trigger: playReveal) { cardScale in
                    mainCard(magicProgress: t)
                        .scaleEffect(cardScale * (isSaving ? 0.6 : 1))
                        .opacity(isSaving ? 0 : 1)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isSaving)
                } animation: { _ in
                    .spring(response: 0.42, dampingFraction: 0.72)
                }
                Spacer(minLength: 24)

                ZStack {
                    if showBottomChrome {
                        bottomChrome
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.6, bounce: 0.4), value: showBottomChrome)

                Spacer(minLength: 24)
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

    private func mainCard(magicProgress: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(DesignTokens.colors.cardStroke, lineWidth: 1)
                )
                .frame(width: 290, height: 349)

            MagicLiftView(image: extractedImage, magicProgress: magicProgress)
                .frame(maxWidth: 260, maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(24)
        }
    }

    private var bottomChrome: some View {
        VStack(spacing: 0) {
            wordLabels
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

    private var wordLabels: some View {
        VStack(spacing: 16) {
            Text(word.learnWord)
                .font(CaptureTypography.detailWordTitle())
                .foregroundStyle(isPending ? DesignTokens.colors.capturesTextSecondary : DesignTokens.colors.capturesTextPrimary)
                .multilineTextAlignment(.center)

            Text(word.nativeWord)
                .font(CaptureTypography.detailPhonetic())
                .foregroundStyle(DesignTokens.colors.capturesTextSecondary)
                .multilineTextAlignment(.center)
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
