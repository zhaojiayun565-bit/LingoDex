import SwiftUI
import UIKit
import AVFoundation

/// Post-capture: edge scan → Metal pixel dissolve on background → card + dot grid → reveal chrome.
struct StickerResultView: View {
    let word: WordEntry
    let extractedImage: UIImage?
    let maskImage: UIImage?
    let capturedImageInfo: CapturedImageInfo?
    let revealPhase: CaptureRevealPhase
    let deps: Dependencies
    let onSave: () -> Void
    let onDismiss: () -> Void
    let onRetry: () -> Void
    let onTryPronunciation: (WordEntry) -> Void

    @State private var isSaving = false
    @State private var isSpeaking = false
    @State private var isSpeakerPulsing = false
    @State private var pixelDissolveProgress: CGFloat = 0

    private var isPending: Bool {
        word.learnWord == "Loading…" || word.learnWord == "Loading..."
    }

    var body: some View {
        GeometryReader { geo in
            let cardScale: CGFloat = (revealPhase == .morphing || revealPhase == .revealed) ? 0.85 : 1.0
            let cardCorner: CGFloat = (revealPhase == .morphing || revealPhase == .revealed) ? 32 : 0
            let dotOpacity: CGFloat = (revealPhase == .morphing || revealPhase == .revealed) ? 1 : 0
            let cardSurfaceOpacity: CGFloat = (revealPhase == .morphing || revealPhase == .revealed) ? 1 : 0

            ZStack {
                Color.black.ignoresSafeArea()

                DesignTokens.colors.background
                    .ignoresSafeArea()
                    .opacity(revealPhase == .scanning || revealPhase == .isolating ? 0 : 1)

                DotGridBackground()
                    .opacity(dotOpacity)
                    .animation(.spring(response: 0.45, dampingFraction: 0.82), value: revealPhase)

                if let capture = capturedImageInfo, revealPhase == .scanning || revealPhase == .isolating {
                    Image(uiImage: capture.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .ignoresSafeArea()
                        .layerEffect(
                            ShaderLibrary.pixelateDissolve(.float(Float(pixelDissolveProgress))),
                            maxSampleOffset: CGSize(width: 64, height: 64)
                        )
                }

                VStack(spacing: 0) {
                    if revealPhase == .revealed {
                        topBar
                    }
                    Spacer(minLength: 12)
                    ZStack {
                        RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                            .fill(Color.white)
                            .opacity(cardSurfaceOpacity)
                            .shadow(color: Color.black.opacity(0.06), radius: 20, y: 10)

                        DotGridBackground()
                            .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
                            .opacity(dotOpacity * 0.85)

                        stickerHero(size: geo.size)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
                    .padding(.horizontal, revealPhase == .scanning || revealPhase == .isolating ? 0 : 20)
                    .scaleEffect(cardScale)
                    .animation(.spring(response: 0.48, dampingFraction: 0.78), value: revealPhase)

                    Spacer(minLength: 12)

                    if revealPhase == .revealed {
                        bottomChrome
                            .transition(
                                .move(edge: .bottom)
                                    .combined(with: .scale(scale: 0.88))
                                    .combined(with: .opacity)
                            )
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.72), value: revealPhase)
            }
        }
        .onChange(of: revealPhase) { _, new in
            if new == .isolating {
                pixelDissolveProgress = 0
                withAnimation(.easeInOut(duration: 0.38)) {
                    pixelDissolveProgress = 1
                }
            } else if new == .scanning {
                pixelDissolveProgress = 0
            }
            if new == .revealed {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
                try? AVAudioSession.sharedInstance().setActive(true)
            }
        }
        .onAppear {
            if revealPhase == .isolating {
                pixelDissolveProgress = 0
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.38)) {
                        pixelDissolveProgress = 1
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stickerHero(size: CGSize) -> some View {
        let maxSticker: CGFloat = min(size.width * 0.88, 340)

        ZStack {
            if revealPhase == .revealed, extractedImage != nil {
                RadialGradient(
                    colors: [
                        DesignTokens.colors.primary.opacity(0.22),
                        DesignTokens.colors.stickerGlow.opacity(0.12),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 20,
                    endRadius: 160
                )
                .frame(width: maxSticker + 40, height: maxSticker + 40)
                .opacity(1)
                .animation(.easeOut(duration: 0.35), value: revealPhase)
            }

            if let img = extractedImage {
                ZStack {
                    if revealPhase == .scanning, let mask = maskImage {
                        edgeScanOutline(mask: mask, maxWidth: maxSticker)
                    }
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: maxSticker, maxHeight: maxSticker * 1.05)
                        .shadow(
                            color: revealPhase == .revealed ? Color.black.opacity(0.15) : .clear,
                            radius: revealPhase == .revealed ? 15 : 0,
                            x: 0,
                            y: revealPhase == .revealed ? 10 : 0
                        )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, revealPhase == .morphing || revealPhase == .revealed ? 28 : 40)
    }

    /// Razor rim using Vision mask + spinning angular wash.
    private func edgeScanOutline(mask: UIImage, maxWidth: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { ctx in
            let angle = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.8) / 2.8 * 360

            Image(uiImage: mask)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: maxWidth)
                .foregroundStyle(
                    AngularGradient(
                        colors: [
                            Color.clear,
                            DesignTokens.colors.primary.opacity(0.15),
                            DesignTokens.colors.primary,
                            DesignTokens.colors.stickerGlow.opacity(0.55),
                            DesignTokens.colors.primary.opacity(0.15),
                            Color.clear
                        ],
                        center: .center,
                        angle: .degrees(angle)
                    )
                )
                .blur(radius: 0.8)
                .allowsHitTesting(false)
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

    private var bottomChrome: some View {
        VStack(spacing: 0) {
            wordLabels
            Spacer(minLength: 28)
            actionButtons
            Spacer(minLength: 24)
            SaveCancelButtons(
                onSave: saveAndAnimate,
                onCancel: nil,
                isSaveDisabled: isSaving
            )
            .padding(.horizontal, 20)
            Spacer(minLength: 48)
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
            } catch { }
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
