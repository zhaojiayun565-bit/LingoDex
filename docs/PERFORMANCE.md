# App loading & performance (LingoDex)

Concise record of what we changed to reduce cold-start friction and speed up capture/processing.

## Launch

- **SwiftData migration** runs in `ContentView`’s `.task` (after first frame), not inside `CapturesViewModel` init.
- **Optional `CapturesViewModel`**: brief `ProgressView` until migration + VM creation; avoids blocking the first paint with migration.
- **`recognitionSync.syncIfNeeded()`** removed from VM init; runs on **scene `.active`** with `load()` only.

## Camera

- **`CameraWarmupCoordinator`**: pre-configures `AVCaptureSession` while user is on **Captures**; session is **consumed** when opening capture flow (faster than cold setup).
- **Preview preset** `.high` (1080p) instead of `.photo` for quicker session startup.
- **`CameraViewController`**: optional **pre-warmed session** + preview layer attach path.
- **`FullScreenCameraView`**: **loading overlay** (“Starting camera…”) until preview is ready; `onPreviewReady` from the VC.

## Object processing

- **Subject lift + Gemini** run **in parallel** (`async let`) when online; offline still does sticker then queue.
- **`SubjectLiftService.warmUp()`**: tiny image through Vision to prime frameworks (background).
- **`GeminiRecognitionClient.warmUp()`**: HEAD to Supabase base URL to warm HTTP (skipped if not signed in).

## First-time / tab / images

- **Service touch**: background init of `imageLoader` + `captureStore` when main content appears.
- **`ImageLoadingService.preloadThumbnails`**: first **12** grid thumbnails after **~0.5s** (utility priority).
- **Photos**: `PHPickerConfiguration` warm-up after short delay.
- **TTS**: silent `speak(" ")` in background so first real playback is faster.

## Key files

| Area | Files |
|------|--------|
| Launch / warm-up | `ContentView.swift`, `SwiftDataMigration.swift` |
| Camera | `CameraWarmupCoordinator.swift`, `CameraViewController.swift`, `FullScreenCameraView.swift`, `CaptureFlowView.swift`, `Dependencies.swift` |
| Processing | `CapturesViewModel.swift`, `SubjectLiftService.swift`, `GeminiRecognitionClient.swift` |
| Images | `ImageLoadingService.swift` |

## Trade-offs

- Camera warm-up uses camera/battery briefly on Captures tab.
- Preloads and warm-ups are **utility-priority** and best-effort (failures are ignored).
