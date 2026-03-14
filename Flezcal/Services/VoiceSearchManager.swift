import Foundation
import Speech
import AVFoundation
import Combine

/// Manages microphone input and speech-to-text transcription.
/// Publishes the live transcript as the user speaks, then a final
/// result when they stop (or tap the mic again to cancel).
@MainActor
class VoiceSearchManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var transcript: String = ""          // live, streaming text
    @Published var isListening: Bool = false
    @Published var permissionDenied: Bool = false
    @Published var error: String? = nil

    // MARK: - Private

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // Callback fired when the user finishes speaking
    var onFinalTranscript: ((String) -> Void)?

    /// Guards against double-fire of `onFinalTranscript` when a queued
    /// `isFinal` result arrives after the user already tapped stop.
    private var didFireFinal = false

    // MARK: - Public API

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.permissionDenied = (status != .authorized)
            }
        }
    }

    func startListening() {
        guard !isListening else { stopListening(); return }
        transcript = ""
        error = nil
        didFireFinal = false

        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    guard granted else {
                        self?.permissionDenied = true
                        return
                    }
                    self?.beginRecognition()
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    guard granted else {
                        self?.permissionDenied = true
                        return
                    }
                    self?.beginRecognition()
                }
            }
        }
    }

    func stopListening() {
        stopListening(submitTranscript: true)
    }

    /// Stops the audio engine and recognition task.
    /// - Parameter submitTranscript: When `true` (default), fires
    ///   `onFinalTranscript` with the current transcript if non-empty.
    ///   Pass `false` when the recognition callback already handled the final result.
    private func stopListening(submitTranscript: Bool) {
        let shouldFire = submitTranscript && !transcript.isEmpty && !didFireFinal
        let pending = shouldFire ? transcript : nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        if let final = pending {
            didFireFinal = true
            onFinalTranscript?(final)
        }
    }

    // MARK: - Private

    private func beginRecognition() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            error = "Speech recognition unavailable right now."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Microphone session failed."
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true   // streams text in real-time

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()
        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, err in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal, !self.didFireFinal {
                        self.didFireFinal = true
                        let final = self.transcript
                        self.stopListening(submitTranscript: false)
                        self.onFinalTranscript?(final)
                    }
                }

                if let err {
                    // Code 1110 = silence timeout — treat as "done speaking"
                    let nsErr = err as NSError
                    if nsErr.code == 1110, !self.transcript.isEmpty, !self.didFireFinal {
                        self.didFireFinal = true
                        let final = self.transcript
                        self.stopListening(submitTranscript: false)
                        self.onFinalTranscript?(final)
                    } else if nsErr.code != 216 { // 216 = task cancelled, ignore
                        self.error = "Could not understand. Please try again."
                        self.stopListening(submitTranscript: false)
                    }
                }
            }
        }
    }
}
