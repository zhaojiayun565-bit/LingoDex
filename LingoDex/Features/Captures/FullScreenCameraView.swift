import AVFoundation
import SwiftUI
import UIKit

/// Full-screen custom camera with viewfinder, X, shutter, and photo library.
/// Uses AVCaptureSession for precise layout control.
struct FullScreenCameraView: View {
    let onImagePicked: (CapturedImageInfo) -> Void
    let onCancel: () -> Void
    let onPhotoLibrary: () -> Void

    @State private var shutterTrigger = 0
    @State private var impactLight = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ZStack {
            CameraPreviewView(onImagePicked: onImagePicked, shutterTrigger: shutterTrigger)

            VStack {
                Spacer()

                ViewfinderFrame()

                Spacer()

                HStack {
                    cameraButton(icon: "xmark", action: onCancel, impact: impactLight)
                    Spacer()
                    ShutterButton(action: { shutterTrigger += 1 })
                    Spacer()
                    cameraButton(icon: "photo.on.rectangle.angled", action: onPhotoLibrary, impact: impactLight)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 44)
            }
        }
        .ignoresSafeArea()
        .onAppear { impactLight.prepare() }
    }

    private func cameraButton(icon: String, action: @escaping () -> Void, impact: UIImpactFeedbackGenerator) -> some View {
        Button(action: {
            impact.impactOccurred()
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

/// L-shaped corner brackets with instruction text underneath.
private struct ViewfinderFrame: View {
    private let cornerLength: CGFloat = 32
    private let strokeWidth: CGFloat = 4
    private let frameWidth: CGFloat = 280
    private let frameHeight: CGFloat = 360

    var body: some View {
        VStack(spacing: 16) {
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

            Text("Please place the object inside the frame.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

private enum CornerAngle {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// L-shaped corner bracket with rounded outer corner.
private struct CornerBracket: View {
    let angle: CornerAngle
    private let strokeWidth: CGFloat = 4
    private let length: CGFloat = 32
    private let cornerRadius: CGFloat = 12

    var body: some View {
        CornerBracketShape(angle: angle, length: length, strokeWidth: strokeWidth, cornerRadius: cornerRadius)
            .fill(.white)
            .frame(width: length, height: length)
    }
}

/// L-shaped path with rounded outer corner. All four corners follow the same pattern:
/// outer corner is rounded; path traces the L boundary counterclockwise from inner corner.
private struct CornerBracketShape: Shape {
    let angle: CornerAngle
    let length: CGFloat
    let strokeWidth: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, length / 3)
        let sw = strokeWidth
        var path = Path()

        switch angle {
        case .topLeft:
            // L: top bar + left bar. Outer rounded corner at (0,0)
            path.move(to: CGPoint(x: sw, y: sw))
            path.addLine(to: CGPoint(x: length, y: sw))
            path.addLine(to: CGPoint(x: length, y: 0))
            path.addLine(to: CGPoint(x: r, y: 0))
            path.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .degrees(270), endAngle: .degrees(180), clockwise: true)
            path.addLine(to: CGPoint(x: 0, y: sw))
            path.addLine(to: CGPoint(x: 0, y: length))
            path.addLine(to: CGPoint(x: sw, y: length))
            path.addLine(to: CGPoint(x: sw, y: sw))
        case .topRight:
            // L: top bar + right bar. Outer rounded corner at (length,0)
            path.move(to: CGPoint(x: length - sw, y: sw))
            path.addLine(to: CGPoint(x: length - sw, y: length))
            path.addLine(to: CGPoint(x: length, y: length))
            path.addLine(to: CGPoint(x: length, y: r))
            path.addArc(center: CGPoint(x: length - r, y: r), radius: r, startAngle: .degrees(0), endAngle: .degrees(270), clockwise: true)
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: sw))
            path.addLine(to: CGPoint(x: length - sw, y: sw))
        case .bottomLeft:
            // L: left bar + bottom bar. Outer rounded corner at (0,length)
            path.move(to: CGPoint(x: sw, y: length - sw))
            path.addLine(to: CGPoint(x: sw, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: length - r))
            path.addArc(center: CGPoint(x: r, y: length - r), radius: r, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
            path.addLine(to: CGPoint(x: length, y: length))
            path.addLine(to: CGPoint(x: length, y: length - sw))
            path.addLine(to: CGPoint(x: sw, y: length - sw))
        case .bottomRight:
            // L: right bar + bottom bar. Outer rounded corner at (length,length)
            // Trace same structure as bottomLeft but mirrored: up right bar, then along bottom
            path.move(to: CGPoint(x: length - sw, y: length - sw))
            path.addLine(to: CGPoint(x: length - sw, y: 0))
            path.addLine(to: CGPoint(x: length, y: 0))
            path.addLine(to: CGPoint(x: length, y: length - r))
            path.addArc(center: CGPoint(x: length - r, y: length - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: 0, y: length))
            path.addLine(to: CGPoint(x: 0, y: length - sw))
            path.addLine(to: CGPoint(x: length - sw, y: length - sw))
        }
        path.closeSubpath()
        return path
    }
}

private struct ShutterButton: View {
    let action: () -> Void
    @State private var impactMedium = UIImpactFeedbackGenerator(style: .medium)

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
            impactMedium.impactOccurred()
        })
        .onAppear { impactMedium.prepare() }
    }
}

private struct CameraPreviewView: UIViewControllerRepresentable {
    let onImagePicked: (CapturedImageInfo) -> Void
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
