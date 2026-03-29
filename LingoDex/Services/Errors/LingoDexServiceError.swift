import Foundation

enum LingoDexServiceError: Error, LocalizedError {
    case invalidImage
    case translationUnavailable
    case recognitionFailed
    case ttsFailed
    case backgroundRemovalFailed
    case supabaseNotConfigured

    var errorDescription: String? {
        switch self {
        case .invalidImage: "Invalid image input."
        case .translationUnavailable: "Translation is not available for this language pairing."
        case .recognitionFailed: "Object recognition failed."
        case .ttsFailed: "Text-to-speech failed."
        case .backgroundRemovalFailed: "Background removal failed. Try on a physical device."
        case .supabaseNotConfigured: "Supabase is not configured. Set `SUPABASE_URL` and `SUPABASE_ANON_KEY` in the app configuration."
        }
    }
}

