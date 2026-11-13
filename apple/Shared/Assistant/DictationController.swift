import AVFoundation
import Observation
import Speech

/// Live dictation for the task chat: microphone → on-device speech recognition (when the device
/// supports it), with partial results as the user speaks.
@MainActor
@Observable
final class DictationController {
    private(set) var isRecording = false
    /// What's been recognised so far in the current dictation.
    private(set) var transcript = ""
    private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func toggle() async {
        if isRecording { stop() } else { await start() }
    }

    func start() async {
        errorMessage = nil
        transcript = ""
        guard await Self.authorize() else {
            #if os(macOS)
            errorMessage = "Allow Emo to use the microphone and speech recognition in System Settings › Privacy & Security."
            #else
            errorMessage = "Allow Emo to use the microphone and speech recognition in Settings › Apps › Emo."
            #endif
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Couldn't start the microphone (\(error.localizedDescription))."
            return
        }
        #endif
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            errorMessage = "No microphone found."
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(appendingTo: request))

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            errorMessage = "Couldn't start the microphone (\(error.localizedDescription))."
            return
        }
        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                guard let self else { return }
                if let text { self.transcript = text }
                if isFinal || failed { self.stop() }
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        isRecording = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// Built outside the main actor: the audio engine calls it on its own thread.
    private nonisolated static func tapBlock(appendingTo request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        nonisolated(unsafe) let request = request   // append(_:) is safe to call from the audio thread
        return { buffer, _ in request.append(buffer) }
    }

    private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}
