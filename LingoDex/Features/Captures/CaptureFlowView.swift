import AVFoundation
import SwiftUI
import UIKit

/// Orchestrates full capture flow: camera → processing → sticker result.
struct CaptureFlowView: View {
    @Binding var isPresented: Bool
    let deps: Dependencies
    @Bindable var viewModel: CapturesViewModel
    var preWarmedSession: AVCaptureSession? = nil
    var preWarmedPhotoOutput: AVCapturePhotoOutput? = nil

    @State private var verificationTarget: WordEntry?
    @State private var isShowingPhotoPicker = false

    var body: some View {
        Group {
            switch viewModel.captureFlowPhase {
            case .camera:
                FullScreenCameraView(
                    onImagePicked: { info in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { await viewModel.processCapturedImage(info) }
                    },
                    onCancel: {
                        viewModel.dismissPending()
                        isPresented = false
                    },
                    onPhotoLibrary: { isShowingPhotoPicker = true },
                    preWarmedSession: preWarmedSession,
                    preWarmedPhotoOutput: preWarmedPhotoOutput
                )
            case .processing:
                if let info = viewModel.pendingCapturedImageInfo {
                    ScanningCaptureView(capturedInfo: info)
                } else {
                    Color.black.opacity(0.85).ignoresSafeArea()
                }
            case .result:
                resultView
            }
        }
        .sheet(item: $verificationTarget) { target in
            SpeechVerifySheet(
                expectedWord: target.learnWord,
                nativeHint: target.nativeWord,
                language: .english
            )
        }
        .sheet(isPresented: $isShowingPhotoPicker) {
            CapturePhotoPicker(
                isPresented: $isShowingPhotoPicker,
                onImagePicked: { image in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let info = CapturedImageInfo(image: image, previewSize: nil)
                    Task { await viewModel.processCapturedImage(info) }
                }
            )
        }
    }

    @ViewBuilder
    private var resultView: some View {
        if let word = viewModel.pendingWord, let image = viewModel.pendingExtractedImage {
            StickerResultView(
                word: word,
                extractedImage: image,
                capturedImageInfo: viewModel.pendingCapturedImageInfo,
                deps: deps,
                onSave: {
                    Task {
                        await viewModel.savePendingWord()
                        isPresented = false
                    }
                },
                onDismiss: {
                    viewModel.dismissPending()
                    isPresented = false
                },
                onRetry: {
                    viewModel.dismissPending()
                },
                onTryPronunciation: {
                    verificationTarget = $0
                }
            )
        }
    }
}

// MARK: - Phase 1: freeze + scan

/// Full-screen frozen capture with subtle “scanning” treatment (no black overlay).
private struct ScanningCaptureView: View {
    let capturedInfo: CapturedImageInfo

    var body: some View {
        ZStack {
            Image(uiImage: capturedInfo.image)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            // Soft frosted veil + animated shimmer sweep
            Rectangle()
                .fill(.clear)
                .background(.thinMaterial.opacity(0.35))
                .ignoresSafeArea()

            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let sweep = CGFloat(t.truncatingRemainder(dividingBy: 2.4)) / 2.4
                let pulse = sin(t * 1.2) * 0.5 + 0.5
                ZStack {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [
                                .clear,
                                DesignTokens.colors.primary.opacity(0.12),
                                DesignTokens.colors.primary.opacity(0.28),
                                DesignTokens.colors.primary.opacity(0.12),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.42)
                        .offset(x: sweep * (geo.size.width + geo.size.width * 0.42) - geo.size.width * 0.21)
                        .blur(radius: 20)
                    }

                    Circle()
                        .stroke(DesignTokens.colors.primary.opacity(0.12 + pulse * 0.22), lineWidth: 2)
                        .frame(width: 120, height: 120)
                        .scaleEffect(0.92 + pulse * 0.12)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }
}
