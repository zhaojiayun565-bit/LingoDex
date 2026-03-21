import SwiftUI
import UIKit

/// Orchestrates full capture flow: camera → processing → sticker result.
struct CaptureFlowView: View {
    @Binding var isPresented: Bool
    let deps: Dependencies
    @Bindable var viewModel: CapturesViewModel

    @State private var verificationTarget: WordEntry?
    @State private var isShowingPhotoPicker = false

    var body: some View {
        Group {
            switch viewModel.captureFlowPhase {
            case .camera:
                FullScreenCameraView(
                    onImagePicked: { image in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { await viewModel.processCapturedImage(image) }
                    },
                    onCancel: {
                        viewModel.dismissPending()
                        isPresented = false
                    },
                    onPhotoLibrary: { isShowingPhotoPicker = true }
                )
            case .processing:
                processingOverlay
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
                    Task { await viewModel.processCapturedImage(image) }
                }
            )
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white)
                Text("Processing...")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private var resultView: some View {
        if let word = viewModel.pendingWord, let image = viewModel.pendingExtractedImage {
            StickerResultView(
                word: word,
                extractedImage: image,
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
                onTryPronunciation: { verificationTarget = $0 }
            )
        }
    }
}
