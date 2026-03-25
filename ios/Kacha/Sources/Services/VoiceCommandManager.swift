import Speech
import AVFoundation
import Combine

// MARK: - Voice Command Manager
// Japanese voice commands for KAGI smart home control.
// Uses iOS Speech framework with ja-JP locale.
// Lightweight voiceprint check (pitch + duration) for authentication.

@MainActor
class VoiceCommandManager: ObservableObject {

    static let shared = VoiceCommandManager()

    // MARK: - Published State

    @Published var isListening = false
    @Published var lastTranscript = ""
    @Published var matchedAction: VoiceAction?
    @Published var isAuthenticated = false
    @Published var authSetupComplete = false
    @Published var authSamplesRecorded = 0
    @Published var errorMessage: String?

    // MARK: - Voice Actions

    enum VoiceAction: String, CaseIterable {
        case unlock     = "unlock"
        case lock       = "lock"
        case homecoming = "homecoming"
        case leaving    = "leaving"
        case sleep      = "sleep"
        case wakeup     = "wakeup"
        case lightOn    = "light_on"
        case lightOff   = "light_off"

        var label: String {
            switch self {
            case .unlock:     return "解錠"
            case .lock:       return "施錠"
            case .homecoming: return "帰宅シーン"
            case .leaving:    return "外出シーン"
            case .sleep:      return "就寝シーン"
            case .wakeup:     return "起床シーン"
            case .lightOn:    return "照明オン"
            case .lightOff:   return "照明オフ"
            }
        }

        var icon: String {
            switch self {
            case .unlock:     return "lock.open.fill"
            case .lock:       return "lock.fill"
            case .homecoming: return "figure.walk.arrival"
            case .leaving:    return "figure.walk.departure"
            case .sleep:      return "moon.stars.fill"
            case .wakeup:     return "sun.and.horizon.fill"
            case .lightOn:    return "lightbulb.fill"
            case .lightOff:   return "lightbulb.slash"
            }
        }

        var color: String {
            switch self {
            case .unlock:     return "10B981"
            case .lock:       return "EF4444"
            case .homecoming: return "10B981"
            case .leaving:    return "3B9FE8"
            case .sleep:      return "F59E0B"
            case .wakeup:     return "E8A838"
            case .lightOn:    return "F59E0B"
            case .lightOff:   return "7a7a95"
            }
        }
    }

    // MARK: - Command Keywords

    private let commands: [(keywords: [String], action: VoiceAction)] = [
        (["開けて", "あけて", "アンロック", "解錠"],       .unlock),
        (["閉めて", "しめて", "ロック", "施錠"],          .lock),
        (["おかえり", "帰宅", "ただいま"],               .homecoming),
        (["おでかけ", "外出", "いってきます"],            .leaving),
        (["おやすみ", "就寝"],                          .sleep),
        (["おはよう", "起床"],                           .wakeup),
        (["電気つけて", "ライトオン", "明るく", "照明つけて"], .lightOn),
        (["電気消して", "ライトオフ", "暗く", "照明消して"],  .lightOff),
    ]

    // MARK: - Speech Recognition

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // MARK: - Voiceprint Authentication

    private let voiceprintKey = "kagi_voiceprint"
    private let requiredSamples = 3

    struct Voiceprint: Codable {
        var averagePitch: Float      // Hz
        var averageDuration: Float   // seconds
        var tolerance: Float         // allowed deviation ratio (0.0 - 1.0)
    }

    // Callback when a command is matched and authenticated
    var onCommandRecognized: ((VoiceAction) -> Void)?

    // MARK: - Lifecycle

    init() {
        loadVoiceprint()
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            errorMessage = "音声認識の許可が必要です"
            return false
        }

        let audioStatus: Bool
        if #available(iOS 17.0, *) {
            audioStatus = await AVAudioApplication.requestRecordPermission()
        } else {
            audioStatus = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        guard audioStatus else {
            errorMessage = "マイクの許可が必要です"
            return false
        }

        return true
    }

    // MARK: - Start / Stop Listening

    func startListening() {
        guard !isListening else { return }
        guard speechRecognizer?.isAvailable == true else {
            errorMessage = "音声認識が利用できません"
            return
        }

        errorMessage = nil
        matchedAction = nil
        lastTranscript = ""

        do {
            try startAudioSession()
            try startRecognition()
            isListening = true
        } catch {
            errorMessage = "音声認識の開始に失敗: \(error.localizedDescription)"
            cleanup()
        }
    }

    func stopListening() {
        guard isListening else { return }
        cleanup()
        isListening = false
    }

    // MARK: - Audio Session

    private func startAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Recognition

    private func startRecognition() throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.lastTranscript = text

                    if let action = self.matchCommand(text) {
                        self.matchedAction = action
                        self.stopListening()
                        self.onCommandRecognized?(action)
                    }
                }

                if error != nil || (result?.isFinal == true) {
                    // Recognition ended naturally or with error
                    if self.isListening && self.matchedAction == nil {
                        self.stopListening()
                    }
                }
            }
        }
    }

    // MARK: - Command Matching

    private func matchCommand(_ text: String) -> VoiceAction? {
        let normalized = text.lowercased()
            .replacingOccurrences(of: " ", with: "")
        for cmd in commands {
            for keyword in cmd.keywords {
                if normalized.contains(keyword.lowercased()) {
                    return cmd.action
                }
            }
        }
        return nil
    }

    // MARK: - Voiceprint Setup

    private var voiceprintSamples: [(pitch: Float, duration: Float)] = []

    func startVoiceprintSample() {
        // Record a short sample of user saying "KAGI"
        // We measure average pitch from the audio buffer
        startListeningForVoiceprint()
    }

    private func startListeningForVoiceprint() {
        guard speechRecognizer?.isAvailable == true else {
            errorMessage = "音声認識が利用できません"
            return
        }

        errorMessage = nil

        do {
            try startAudioSession()

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            var pitchAccumulator: Float = 0
            var pitchCount: Int = 0
            let startTime = Date()

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)

                // Simple pitch estimation from RMS energy
                let channelData = buffer.floatChannelData?[0]
                let frameLength = Int(buffer.frameLength)
                if let data = channelData, frameLength > 0 {
                    var sum: Float = 0
                    for i in 0..<frameLength {
                        sum += abs(data[i])
                    }
                    let avg = sum / Float(frameLength)
                    if avg > 0.01 { // Voice activity threshold
                        // Use zero-crossing rate as rough pitch proxy
                        var crossings: Int = 0
                        for i in 1..<frameLength {
                            if (data[i] >= 0) != (data[i-1] >= 0) {
                                crossings += 1
                            }
                        }
                        let sampleRate = Float(recordingFormat.sampleRate)
                        let zcr = Float(crossings) / 2.0 * sampleRate / Float(frameLength)
                        pitchAccumulator += zcr
                        pitchCount += 1
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()

            recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self = self else { return }

                    if let result = result {
                        let text = result.bestTranscription.formattedString.lowercased()
                        // Wait until we hear "kagi" or "カギ" or "鍵"
                        if text.contains("kagi") || text.contains("カギ") || text.contains("鍵")
                            || text.contains("かぎ") {
                            let duration = Float(Date().timeIntervalSince(startTime))
                            let avgPitch = pitchCount > 0 ? pitchAccumulator / Float(pitchCount) : 200
                            self.voiceprintSamples.append((pitch: avgPitch, duration: duration))
                            self.authSamplesRecorded = self.voiceprintSamples.count
                            self.cleanup()

                            if self.voiceprintSamples.count >= self.requiredSamples {
                                self.saveVoiceprint()
                            }
                            return
                        }
                    }

                    if error != nil || (result?.isFinal == true) {
                        self.cleanup()
                        if self.voiceprintSamples.count < self.requiredSamples {
                            self.errorMessage = "「カギ」と聞き取れませんでした。もう一度お試しください。"
                        }
                    }
                }
            }

            // Auto-stop after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self = self else { return }
                if self.audioEngine.isRunning {
                    self.cleanup()
                    if self.voiceprintSamples.count < self.requiredSamples
                        && self.voiceprintSamples.count == self.authSamplesRecorded {
                        self.errorMessage = "「カギ」と聞き取れませんでした。もう一度お試しください。"
                    }
                }
            }
        } catch {
            errorMessage = "録音の開始に失敗: \(error.localizedDescription)"
            cleanup()
        }
    }

    private func saveVoiceprint() {
        guard voiceprintSamples.count >= requiredSamples else { return }

        let avgPitch = voiceprintSamples.map(\.pitch).reduce(0, +) / Float(voiceprintSamples.count)
        let avgDuration = voiceprintSamples.map(\.duration).reduce(0, +) / Float(voiceprintSamples.count)

        let voiceprint = Voiceprint(
            averagePitch: avgPitch,
            averageDuration: avgDuration,
            tolerance: 0.35 // 35% deviation allowed
        )

        if let data = try? JSONEncoder().encode(voiceprint) {
            UserDefaults.standard.set(data, forKey: voiceprintKey)
        }

        authSetupComplete = true
        isAuthenticated = true
        voiceprintSamples = []
    }

    private func loadVoiceprint() {
        if let data = UserDefaults.standard.data(forKey: voiceprintKey),
           let _ = try? JSONDecoder().decode(Voiceprint.self, from: data) {
            authSetupComplete = true
        }
    }

    func resetVoiceprint() {
        UserDefaults.standard.removeObject(forKey: voiceprintKey)
        authSetupComplete = false
        isAuthenticated = false
        authSamplesRecorded = 0
        voiceprintSamples = []
    }

    /// Authenticate by checking voice features against stored voiceprint.
    /// If no voiceprint is set up, authentication is skipped (always passes).
    func authenticate() async -> Bool {
        guard authSetupComplete else {
            // No voiceprint set up — skip check
            isAuthenticated = true
            return true
        }

        guard let data = UserDefaults.standard.data(forKey: voiceprintKey),
              let stored = try? JSONDecoder().decode(Voiceprint.self, from: data) else {
            isAuthenticated = true
            return true
        }

        return await withCheckedContinuation { continuation in
            // Record a short sample and compare
            var resolved = false

            do {
                try startAudioSession()

                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                recognitionRequest = request

                let inputNode = audioEngine.inputNode
                let recordingFormat = inputNode.outputFormat(forBus: 0)
                var pitchAccumulator: Float = 0
                var pitchCount: Int = 0
                let startTime = Date()

                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                    self?.recognitionRequest?.append(buffer)

                    let channelData = buffer.floatChannelData?[0]
                    let frameLength = Int(buffer.frameLength)
                    if let channelData, frameLength > 0 {
                        var sum: Float = 0
                        for i in 0..<frameLength { sum += abs(channelData[i]) }
                        let avg = sum / Float(frameLength)
                        if avg > 0.01 {
                            var crossings = 0
                            for i in 1..<frameLength {
                                if (channelData[i] >= 0) != (channelData[i-1] >= 0) { crossings += 1 }
                            }
                            let sampleRate = Float(recordingFormat.sampleRate)
                            let zcr = Float(crossings) / 2.0 * sampleRate / Float(frameLength)
                            pitchAccumulator += zcr
                            pitchCount += 1
                        }
                    }
                }

                audioEngine.prepare()
                try audioEngine.start()

                recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                    Task { @MainActor in
                        guard let self = self, !resolved else { return }

                        if let result = result {
                            let text = result.bestTranscription.formattedString.lowercased()
                            if text.contains("kagi") || text.contains("カギ") || text.contains("鍵")
                                || text.contains("かぎ") {
                                let duration = Float(Date().timeIntervalSince(startTime))
                                let avgPitch = pitchCount > 0 ? pitchAccumulator / Float(pitchCount) : 200

                                let pitchOk = abs(avgPitch - stored.averagePitch) / max(stored.averagePitch, 1)
                                    <= stored.tolerance
                                let durationOk = abs(duration - stored.averageDuration) / max(stored.averageDuration, 0.1)
                                    <= stored.tolerance * 2 // duration more variable

                                let passed = pitchOk || durationOk // lenient: either match is ok
                                self.isAuthenticated = passed
                                self.cleanup()
                                resolved = true
                                continuation.resume(returning: passed)
                                return
                            }
                        }

                        if error != nil || (result?.isFinal == true) {
                            self.cleanup()
                            self.isAuthenticated = false
                            if !resolved {
                                resolved = true
                                continuation.resume(returning: false)
                            }
                        }
                    }
                }

                // Timeout after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard !resolved else { return }
                    self?.cleanup()
                    resolved = true
                    Task { @MainActor in
                        self?.isAuthenticated = false
                    }
                    continuation.resume(returning: false)
                }

            } catch {
                if !resolved {
                    resolved = true
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Cleanup

    private func cleanup() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
