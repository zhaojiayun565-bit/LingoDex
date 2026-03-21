import Foundation

struct Dependencies {
    let objectRecognition: any ObjectRecognitionClient
    let translation: any TranslationClient
    let tts: any TTSClient
    let speechVerification: any SpeechVerificationClient
    let storyGenerator: any StoryGeneratorClient
    let auth: any AuthClient
    let localStore: LocalLingoDexStore
    let backgroundRemoval: BackgroundRemovalService
    let imageLoader: ImageLoadingService
}

extension Dependencies {
    static let live: Dependencies = {
        let imagesDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("lingodex_images", isDirectory: true)
        return Dependencies(
            objectRecognition: AppleVisionObjectRecognitionClient(),
            translation: AppleTranslationClient(),
            tts: AppleTTSClient(),
            speechVerification: MockSpeechVerificationClient(),
            storyGenerator: LocalStoryGeneratorClient(),
            auth: SupabaseAuthClient(),
            localStore: LocalLingoDexStore(),
            backgroundRemoval: BackgroundRemovalService(),
            imageLoader: ImageLoadingService(imagesDirectoryURL: imagesDir)
        )
    }()
}

