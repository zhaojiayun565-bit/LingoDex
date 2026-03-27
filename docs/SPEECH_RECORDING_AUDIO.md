# Speech recording — what we fixed

## Problem

Recording UI froze or deadlocked because **SwiftUI’s `@MainActor` controller** mixed with **Core Audio / Speech** on the wrong threads and in the wrong order (session activation, engine tap, `recognitionTask`, teardown, playback session restore).

## What we did

1. **`SpeechEngineBackend`** — All `AVAudioEngine`, `SFSpeechRecognizer`, request/task, and `WaveformLevelBuffer` live off the controller. UI only holds state and forwards callbacks.

2. **Serial `audioQueue`** — `DispatchQueue(label: "com.lingodex.SpeechEngine", qos: .userInitiated)` runs **all** AVFoundation lifecycle work (start, stop, finalize, teardown, playback restore) in **one ordered sequence** so teardown (e.g. `.playback`) never races the next session’s `.playAndRecord`.

3. **Tap closure** — No `self` / MainActor in the tap; RMS every buffer; **`onLevel` throttled ~25fps** (`CACurrentMediaTime`) while the level buffer stays accurate.

4. **`stopAndFinalize()`** — **Stop engine → remove tap → `endAudio()`** so buffers never append to a finalized request while the engine is running.

5. **Controller** — No redundant `stopByUser()` before `start`; backend’s `start` begins with teardown on the same queue.

Result: hardware init and teardown stay off the main thread and **strictly serialized**, so recording start/stop and repeat sessions stay stable.
