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
}

extension Dependencies {
    static let live = Dependencies(
        objectRecognition: AppleVisionObjectRecognitionClient(),
        translation: AppleTranslationClient(),
        tts: AppleTTSClient(),
        speechVerification: MockSpeechVerificationClient(),
        storyGenerator: LocalStoryGeneratorClient(),
        auth: SupabaseAuthClient(),
        localStore: LocalLingoDexStore(),
        backgroundRemoval: BackgroundRemovalService()
    )
}

