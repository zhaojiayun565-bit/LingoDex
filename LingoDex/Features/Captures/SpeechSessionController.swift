import Foundation
import SwiftUI
import Speech
import AVFoundation
import Observation
import os

@MainActor
@Observable
final class SpeechSessionController {
    enum StopOrigin: String {
        case callbackResult
        case userCancel
    }

    var isListening = false
    var transcript: String = ""
    var errorMessage: String?
    var waveform: [CGFloat] = Array(repeating: 0.15, count: 24)

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recordingTimeoutTask: Task<Void, Never>?
    private var waveformRenderTask: Task<Void, Never>?
    private var isShuttingDown = false
    private var lastTranscriptCommitAt = Date.distantPast
    private var onFinalTranscript: ((String) -> Void)?

    private var speechRecognizer: SFSpeechRecognizer?
    private var audioEngine = AVAudioEngine()
    private let waveformLevelBuffer = WaveformLevelBuffer()
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

        teardown(origin: .userCancel)
        clearDisplayState()
        lastTranscriptCommitAt = .distantPast
        onFinalTranscript = onFinal

        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language.localeTag))
        guard let speechRecognizer else {
            errorMessage = "Speech recognition is not available on this device."
            logger.error("start: recognizer unavailable")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = shouldReportPartialResults
        recognitionRequest = request

        let localRequest = request
        let localLevelBuffer = self.waveformLevelBuffer

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        logger.debug("start: install tap")
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            if let channelData = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                let channelDataArray = UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength))
                var sumSquares: Float = 0
                for sample in channelDataArray {
                    sumSquares += sample * sample
                }
                let rms = sqrt(sumSquares / Float(buffer.frameLength))
                let level = min(max(rms * 12, 0.05), 1.0)
                localLevelBuffer.set(level: CGFloat(level))
            }
            localRequest.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    let incomingTranscript = result.bestTranscription.formattedString
                    let now = Date()
                    let shouldCommit = result.isFinal
                        || incomingTranscript != self.transcript
                            && now.timeIntervalSince(self.lastTranscriptCommitAt) >= 0.12
                    if shouldCommit {
                        self.transcript = incomingTranscript
                        self.lastTranscriptCommitAt = now
                    }
                    if result.isFinal {
                        self.logger.debug("callback: final result")
                        self.isListening = false
                        self.onFinalTranscript?(self.transcript)
                        self.teardown(origin: .callbackResult)
                    }
                } else if let error {
                    self.logger.error("callback: error=\(error.localizedDescription, privacy: .public)")
                    self.isListening = false
                    self.errorMessage = error.localizedDescription
                    self.teardown(origin: .callbackResult)
                }
            }
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            try audioEngine.start()
            logger.debug("start: audio engine started")
            isListening = true
            startWaveformRenderLoop()
            startRecordingTimeout(seconds: timeoutSeconds)
        } catch {
            logger.error("start: engine error=\(error.localizedDescription, privacy: .public)")
            errorMessage = "Audio engine could not start."
            isListening = false
            teardown(origin: .userCancel)
        }
    }

    func stopAndFinalize() {
        guard isListening else { return }
        logger.debug("stopAndFinalize: endAudio")
        isListening = false
        recognitionRequest?.endAudio()
    }

    func stopByUser() {
        logger.debug("stopByUser")
        isListening = false
        teardown(origin: .userCancel)
    }

    func teardown(origin: StopOrigin) {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        logger.debug("teardown: origin=\(origin.rawValue, privacy: .public)")

        waveformRenderTask?.cancel()
        waveformRenderTask = nil
        recordingTimeoutTask?.cancel()
        recordingTimeoutTask = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        if origin == .userCancel {
            recognitionTask?.cancel()
        }
        recognitionTask = nil
        recognitionRequest = nil
        onFinalTranscript = nil

        restorePlaybackAudioSession()
        isShuttingDown = false
    }

    private func startRecordingTimeout(seconds: UInt64) {
        recordingTimeoutTask?.cancel()
        recordingTimeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, isListening else { return }
            logger.error("timeout: recording exceeded \(seconds, privacy: .public)s")
            isListening = false
            errorMessage = "Recording timed out. Please try again."
            teardown(origin: .userCancel)
        }
    }

    private func startWaveformRenderLoop() {
        waveformRenderTask?.cancel()
        waveformRenderTask = Task { @MainActor in
            while !Task.isCancelled && isListening {
                try? await Task.sleep(for: .milliseconds(40))
                let level = waveformLevelBuffer.level()
                var next = waveform
                for i in 0..<next.count {
                    let jitter = CGFloat.random(in: -0.08...0.08)
                    let target = max(0.12, min(1.0, level + jitter))
                    next[i] = max(next[i] * 0.85, target)
                }
                waveform = next
            }
        }
    }

    private func restorePlaybackAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? AVAudioSession.sharedInstance().setActive(true)
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
