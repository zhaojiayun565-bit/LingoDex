import SwiftUI
import UIKit
import PhotosUI

/// Presents the system photo picker (PHPicker) for selecting images from the library.
struct CapturePhotoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onImagePicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onImagePicked: onImagePicked)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        @Binding private var isPresented: Bool
        private let onImagePicked: (UIImage) -> Void

        init(isPresented: Binding<Bool>, onImagePicked: @escaping (UIImage) -> Void) {
            self._isPresented = isPresented
            self.onImagePicked = onImagePicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            defer { isPresented = false }
            guard let result = results.first else { return }
            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage else { return }
                Task { @MainActor in
                    self?.onImagePicked(image)
                }
            }
        }
    }
}
