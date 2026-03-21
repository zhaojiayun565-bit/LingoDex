import Foundation

/// Services are lazy so only those needed for the first frame are created at launch.
final class Dependencies {
    lazy var objectRecognition: any ObjectRecognitionClient = AppleVisionObjectRecognitionClient()
    lazy var translation: any TranslationClient = AppleTranslationClient()
    lazy var tts: any TTSClient = KokoroTTSClient(avSpeechFallback: AppleTTSClient())
    lazy var speechVerification: any SpeechVerificationClient = MockSpeechVerificationClient()
    lazy var storyGenerator: any StoryGeneratorClient = LocalStoryGeneratorClient()
    lazy var auth: any AuthClient = SupabaseAuthClient()
    lazy var localStore: LocalLingoDexStore = LocalLingoDexStore()
    lazy var backgroundRemoval: BackgroundRemovalService = BackgroundRemovalService()
    lazy var imageLoader: ImageLoadingService = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("lingodex_images", isDirectory: true)
        return ImageLoadingService(imagesDirectoryURL: dir)
    }()
}

extension Dependencies {
    static let live = Dependencies()
}

