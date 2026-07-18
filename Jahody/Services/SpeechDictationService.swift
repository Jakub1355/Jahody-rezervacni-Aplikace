import Foundation
import Speech
import AVFoundation

/// Živý převod řeči na text (česky) pro nadiktování objednávky.
/// Když zařízení umí rozpoznávání na zařízení, běží i offline — na farmě
/// není vždy signál.
@MainActor
final class SpeechDictationService: ObservableObject {
    /// Průběžný přepis (aktualizuje se během mluvení).
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?
    /// Uživatel odepřel mikrofon nebo rozpoznávání řeči v systémových právech.
    @Published private(set) var permissionDenied = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "cs-CZ"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Je rozpoznávání české řeči na tomto zařízení dostupné?
    var isAvailable: Bool {
        recognizer?.isAvailable ?? false
    }

    func toggle() {
        isRecording ? stop() : start()
    }

    func start() {
        guard !isRecording else { return }
        errorMessage = nil
        transcript = ""
        Task {
            guard await requestPermissions() else {
                permissionDenied = true
                return
            }
            do {
                try beginRecording()
            } catch {
                errorMessage = "Diktování se nepodařilo spustit: \(error.localizedDescription)"
                cleanUp()
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        request?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
        // task doběhne a doplní finální přepis; request/task uvolní finishTask.
    }

    func reset() {
        stop()
        transcript = ""
        errorMessage = nil
    }

    // MARK: - Práva

    private func requestPermissions() async -> Bool {
        let speechAuthorized: Bool = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAuthorized else { return false }

        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Nahrávání

    private func beginRecording() throws {
        task?.cancel()
        task = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.finishTask()
                }
            }
        }
    }

    private func finishTask() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        isRecording = false
    }

    private func cleanUp() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request = nil
        task = nil
        isRecording = false
    }
}
