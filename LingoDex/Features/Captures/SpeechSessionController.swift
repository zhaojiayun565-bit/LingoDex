import Foundation
import SwiftUI
import Speech
import AVFoundation
import Observation
import QuartzCore
import os

@MainActor
@Observable
final class SpeechSessionController {
    var isListening = false
    var transcript: String = ""
    var errorMessage: String?
    var waveform: [CGFloat] = Array(repeating: 0.15, count: 24)

    private let backend = SpeechEngineBackend()
    private let logger = Logger(subsystem: "com.lingodex.app", category: "SpeechSession")

    func clearDisplayState() {
        transcript = ""
        errorMessage = nil
        waveform = Array(repeating: 0.15, count: 24)
    }

    func requestPermissions() async -> Bool {
        logger.debug("requestPermissions: start")
        let speechOk = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechOk else {
            logger.error("requestPermissions: speech denied")
            return false
        }
        let micOk = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        logger.debug("requestPermissions: mic=\(micOk, privacy: .public)")
        return micOk
    }

    func start(
        language: Language,
        shouldReportPartialResults: Bool,
        timeoutSeconds: UInt64 = 12,
        onFinal: @escaping (String) -> Void
    ) {
        guard !isListening else { return }
        logger.debug("start: locale=\(language.localeTag, privacy: .public)")

        backend.stopByUser()
        clearDisplayState()
        isListening = true

        backend.start(
            languageTag: language.localeTag,
            shouldReportPartialResults: shouldReportPartialResults,
            timeoutSeconds: timeoutSeconds,
            onTranscript: { [weak self] text, isFinal in
                Task { @MainActor in
                    guard let self else { return }
                    self.transcript = text
                    if isFinal {
                        self.isListening = false
                        onFinal(text)
                        self.backend.stopFromCallback()
                    }
                }
            },
            onError: { [weak self] message in
                Task { @MainActor in
                    guard let self else { return }
                    self.logger.error("callback: error=\(message, privacy: .public)")
                    self.errorMessage = message
                    self.isListening = false
                    self.backend.stopFromCallback()
                }
            },
            onLevel: { [weak self] level in
                Task { @MainActor in
                    guard let self, self.isListening else { return }
                    self.applySmoothedWaveformLevel(level)
                }
            },
            onStarted: { [weak self] in
                Task { @MainActor in
                    self?.logger.debug("start: audio engine started")
                }
            }
        )
    }

    func stopAndFinalize() {
        guard isListening else { return }
        logger.debug("stopAndFinalize: endAudio")
        isListening = false
        backend.stopAndFinalize()
    }

    func stopByUser() {
        logger.debug("stopByUser")
        isListening = false
        backend.stopByUser()
    }

    /// Smooths throttled ~25fps level samples into the bar array (no random jitter — avoids jagged jumps).
    private func applySmoothedWaveformLevel(_ level: CGFloat) {
        let clamped = max(0.12, min(1.0, level))
        var next = waveform
        let count = next.count
        guard count > 0 else { return }
        for i in 0..<count {
            let t = count == 1 ? 0.5 : CGFloat(i) / CGFloat(count - 1)
            let spread = CGFloat(0.92 + 0.16 * (0.5 + 0.5 * sin(Double(i) * 0.65)))
            let barTarget = max(0.12, min(1.0, clamped * spread))
            let blended = next[i] * 0.78 + barTarget * 0.22
            next[i] = max(0.12, min(1.0, blended + (t - 0.5) * 0.02))
        }
        waveform = next
    }
}

private final class SpeechEngineBackend: @unchecked Sendable {
    private enum StopOrigin {
        case callbackResult
        case userCancel
    }

    private let lock = NSLock()
    private var speechRecognizer: SFSpeechRecognizer?
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recordingTimeoutTask: Task<Void, Never>?
    private var isShuttingDown = false
    private let waveformLevelBuffer = WaveformLevelBuffer()
    private let logger = Logger(subsystem: "com.lingodex.app", category: "SpeechEngineBackend")

    /// Starts speech engine and recognition fully off the main thread.
    func start(
        languageTag: String,
        shouldReportPartialResults: Bool,
        timeoutSeconds: UInt64,
        onTranscript: @escaping @Sendable (String, Bool) -> Void,
        onError: @escaping @Sendable (String) -> Void,
        onLevel: @escaping @Sendable (CGFloat) -> Void,
        onStarted: @escaping @Sendable () -> Void
    ) {
        Task.detached { [weak self] in
            guard let self else { return }
            self.teardown(origin: .userCancel)
            do {
                let recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageTag))
                guard let recognizer else {
                    onError("Speech recognition is not available on this device.")
                    return
                }
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = shouldReportPartialResults
                let engine = AVAudioEngine()
                let localLevelBuffer = self.waveformLevelBuffer
                let localRequest = request
                final class LevelEmitThrottle: @unchecked Sendable {
                    var lastOnLevelTime: CFTimeInterval = 0
                }
                let levelEmitThrottle = LevelEmitThrottle()
                let minLevelEmitInterval: CFTimeInterval = 0.04

                try AVAudioSession.sharedInstance().setCategory(
                    .playAndRecord,
                    mode: .measurement,
                    options: [.defaultToSpeaker, .duckOthers, .allowBluetooth]
                )
                try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)

                let inputNode = engine.inputNode
                let format = inputNode.outputFormat(forBus: 0)
                inputNode.removeTap(onBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                    if let channelData = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                        let channelDataArray = UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength))
                        var sumSquares: Float = 0
                        for sample in channelDataArray {
                            sumSquares += sample * sample
                        }
                        let rms = sqrt(sumSquares / Float(buffer.frameLength))
                        let level = min(max(rms * 12, 0.05), 1.0)
                        let cgLevel = CGFloat(level)
                        localLevelBuffer.set(level: cgLevel)
                        let now = CACurrentMediaTime()
                        if now - levelEmitThrottle.lastOnLevelTime >= minLevelEmitInterval {
                            levelEmitThrottle.lastOnLevelTime = now
                            onLevel(cgLevel)
                        }
                    }
                    localRequest.append(buffer)
                }

                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let result {
                        onTranscript(result.bestTranscription.formattedString, result.isFinal)
                    } else if let error {
                        onError(error.localizedDescription)
                    }
                }

                self.lock.lock()
                self.speechRecognizer = recognizer
                self.audioEngine = engine
                self.recognitionRequest = request
                self.recognitionTask = task
                self.isShuttingDown = false
                self.lock.unlock()

                self.startRecordingTimeout(seconds: timeoutSeconds, onTimeout: onError)

                engine.prepare()
                try engine.start()
                onStarted()
            } catch {
                self.logger.error("start: engine error=\(error.localizedDescription, privacy: .public)")
                onError("Audio engine could not start.")
                self.stopFromCallback()
            }
        }
    }

    /// Ends audio for final transcript processing.
    func stopAndFinalize() {
        Task.detached { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let request = self.recognitionRequest
            self.lock.unlock()
            request?.endAudio()
        }
    }

    /// Stops backend from explicit user cancellation.
    func stopByUser() {
        Task.detached { [weak self] in
            self?.teardown(origin: .userCancel)
        }
    }

    /// Stops backend from recognition callback completion/error.
    func stopFromCallback() {
        Task.detached { [weak self] in
            self?.teardown(origin: .callbackResult)
        }
    }

    private func startRecordingTimeout(
        seconds: UInt64,
        onTimeout: @escaping @Sendable (String) -> Void
    ) {
        recordingTimeoutTask?.cancel()
        recordingTimeoutTask = Task.detached { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self else { return }
            self.lock.lock()
            let activeRequest = self.recognitionRequest
            self.lock.unlock()
            guard activeRequest != nil else { return }
            onTimeout("Recording timed out. Please try again.")
            self.stopByUser()
        }
    }

    private func teardown(origin: StopOrigin) {
        lock.lock()
        if isShuttingDown {
            lock.unlock()
            return
        }
        isShuttingDown = true
        let task = recognitionTask
        let request = recognitionRequest
        let engine = audioEngine
        recordingTimeoutTask?.cancel()
        recordingTimeoutTask = nil
        recognitionTask = nil
        recognitionRequest = nil
        lock.unlock()

        if origin == .userCancel {
            request?.endAudio()
            task?.cancel()
        }

        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        restorePlaybackAudioSession()

        lock.lock()
        isShuttingDown = false
        lock.unlock()
    }

    private func restorePlaybackAudioSession() {
        Task.detached {
            try? AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }
}

private final class WaveformLevelBuffer {
    private let lock = NSLock()
    private var latestLevel: CGFloat = 0.15

    func set(level: CGFloat) {
        lock.lock()
        latestLevel = level
        lock.unlock()
    }

    func level() -> CGFloat {
        lock.lock()
        let value = latestLevel
        lock.unlock()
        return value
    }
}
