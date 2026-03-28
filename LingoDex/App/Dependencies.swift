import Foundation
import SwiftData
import Supabase

/// Services are lazy so only those needed for the first frame are created at launch.
final class Dependencies {
    var modelContext: ModelContext { LingoDexApp.modelContainer.mainContext }
    var modelContainer: ModelContainer { LingoDexApp.modelContainer }

    lazy var supabase: SupabaseClient = {
        let urlString = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String)
            ?? ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? ""
        let key = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String)
            ?? ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? ""
        let url = URL(string: urlString) ?? URL(string: "https://placeholder.supabase.co")!
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }()

    lazy var captureStore: SwiftDataCaptureStore = SwiftDataCaptureStore(
        modelContext: modelContext,
        modelContainer: modelContainer,
        imageStore: localStore
    )
    lazy var objectRecognition: any ObjectRecognitionClient = AppleVisionObjectRecognitionClient()
    lazy var translation: any TranslationClient = AppleTranslationClient()
    lazy var tts: any TTSClient = KokoroTTSClient(avSpeechFallback: AppleTTSClient())
    lazy var speechVerification: any SpeechVerificationClient = MockSpeechVerificationClient()
    lazy var auth: SupabaseAuthClient = SupabaseAuthClient(supabase: supabase)
    lazy var localStore: LocalLingoDexStore = LocalLingoDexStore()
    lazy var backgroundRemoval: BackgroundRemovalService = BackgroundRemovalService()
    lazy var subjectLift: SubjectLiftService = SubjectLiftService()
    lazy var networkMonitor: NetworkMonitor = NetworkMonitor()
    lazy var geminiRecognition: GeminiRecognitionClient = {
        let urlString = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String)
            ?? ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? ""
        let key = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String)
            ?? ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? ""
        let url = URL(string: urlString) ?? URL(string: "https://placeholder.supabase.co")!
        return GeminiRecognitionClient(supabaseURL: url, anonKey: key) { [weak self] in
            self?.auth.accessToken
        }
    }()
    lazy var recognitionSync: RecognitionSyncService = RecognitionSyncService(
        captureStore: captureStore,
        imageStore: localStore,
        geminiClient: geminiRecognition,
        networkMonitor: networkMonitor
    )
    lazy var imageLoader: ImageLoadingService = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("lingodex_images", isDirectory: true)
        return ImageLoadingService(imagesDirectoryURL: dir)
    }()
    lazy var cameraWarmup: CameraWarmupCoordinator = CameraWarmupCoordinator()
}

extension Dependencies {
    static let live = Dependencies()
}

