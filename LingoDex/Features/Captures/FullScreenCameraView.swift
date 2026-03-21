import AVFoundation
import SwiftUI
import UIKit

/// Full-screen custom camera with viewfinder, date, X, shutter, and photo library.
/// Uses AVCaptureSession for precise layout control.
struct FullScreenCameraView: View {
    let onImagePicked: (UIImage) -> Void
    let onCancel: () -> Void
    let onPhotoLibrary: () -> Void

    @State private var shutterTrigger = 0

    var body: some View {
        ZStack {
            CameraPreviewView(onImagePicked: onImagePicked, shutterTrigger: shutterTrigger)

            VStack {
                // Top: date (respects safe area)
                HStack {
                    Text(dateString)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)

                Spacer()

                // Center: viewfinder
                ViewfinderFrame()

                Spacer()

                // Bottom bar: X, shutter, gallery
                HStack {
                    cameraButton(icon: "xmark", action: onCancel)
                    Spacer()
                    ShutterButton(action: { shutterTrigger += 1 })
                    Spacer()
                    cameraButton(icon: "photo.on.rectangle.angled", action: onPhotoLibrary)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 44)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.dateFormat = "M月d"
        return formatter.string(from: Date())
    }

    private func cameraButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// L-shaped corner brackets with instruction text.
private struct ViewfinderFrame: View {
    private let cornerLength: CGFloat = 32
    private let strokeWidth: CGFloat = 4
    private let frameWidth: CGFloat = 280
    private let frameHeight: CGFloat = 360

    var body: some View {
        ZStack {
            // 4 L-shaped corners
            ZStack(alignment: .topLeading) {
                CornerBracket(angle: .topLeft)
                    .frame(width: cornerLength, height: cornerLength)
                CornerBracket(angle: .topRight)
                    .frame(width: cornerLength, height: cornerLength)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                CornerBracket(angle: .bottomLeft)
                    .frame(width: cornerLength, height: cornerLength)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                CornerBracket(angle: .bottomRight)
                    .frame(width: cornerLength, height: cornerLength)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .frame(width: frameWidth, height: frameHeight)

            Text("请将物体置于框内")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .padding(.top, frameHeight / 2 + 24)
        }
    }
}

private enum CornerAngle {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// L-shaped corner drawn with rectangles (avoids Canvas issues on some toolchains).
private struct CornerBracket: View {
    let angle: CornerAngle
    private let strokeWidth: CGFloat = 4
    private let length: CGFloat = 32

    var body: some View {
        Group {
            switch angle {
            case .topLeft:
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(.white).frame(width: length, height: strokeWidth)
                    Spacer().frame(height: strokeWidth)
                    Rectangle().fill(.white).frame(width: strokeWidth, height: length - strokeWidth)
                }
                .frame(width: length, height: length, alignment: .topLeading)
            case .topRight:
                VStack(alignment: .trailing, spacing: 0) {
                    Rectangle().fill(.white).frame(width: length, height: strokeWidth)
                    Spacer().frame(height: strokeWidth)
                    Rectangle().fill(.white).frame(width: strokeWidth, height: length - strokeWidth)
                }
                .frame(width: length, height: length, alignment: .topTrailing)
            case .bottomLeft:
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(.white).frame(width: strokeWidth, height: length - strokeWidth)
                    Spacer().frame(height: strokeWidth)
                    Rectangle().fill(.white).frame(width: length, height: strokeWidth)
                }
                .frame(width: length, height: length, alignment: .bottomLeading)
            case .bottomRight:
                VStack(alignment: .trailing, spacing: 0) {
                    Rectangle().fill(.white).frame(width: strokeWidth, height: length - strokeWidth)
                    Spacer().frame(height: strokeWidth)
                    Rectangle().fill(.white).frame(width: length, height: strokeWidth)
                }
                .frame(width: length, height: length, alignment: .bottomTrailing)
            }
        }
    }
}

private struct ShutterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.yellow, .green, .blue, .pink, .yellow],
                            center: .center
                        )
                    )
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(.white)
                    .frame(width: 64, height: 64)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { _ in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        })
    }
}

private struct CameraPreviewView: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    let shutterTrigger: Int

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onImagePicked = onImagePicked
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.handleShutterTrigger(shutterTrigger)
    }
}
