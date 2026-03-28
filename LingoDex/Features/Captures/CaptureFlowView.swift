import AVFoundation
import SwiftUI
import UIKit

/// Orchestrates full capture flow: camera → unified post-capture reveal (no view swap mid-animation).
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
            case .processing, .result:
                postCaptureView
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
    private var postCaptureView: some View {
        if let word = viewModel.pendingWord,
           viewModel.pendingCapturedImageInfo != nil {
            StickerResultView(
                word: word,
                extractedImage: viewModel.pendingExtractedImage,
                maskImage: viewModel.pendingMaskImage,
                capturedImageInfo: viewModel.pendingCapturedImageInfo,
                revealPhase: viewModel.captureRevealPhase,
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
        } else {
            Color.black.opacity(0.85).ignoresSafeArea()
        }
    }
}
