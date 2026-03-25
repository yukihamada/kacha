import SwiftUI

// MARK: - Voice Control View
// Full-screen sheet with mic button, waveform animation, recognized text, and matched action.

struct VoiceControlView: View {
    @StateObject private var voiceManager = VoiceCommandManager.shared
    @Environment(\.dismiss) private var dismiss

    // Waveform animation
    @State private var wavePhase: Double = 0
    @State private var waveAmplitude: Double = 0.3
    @State private var permissionsGranted = false
    @State private var showAuthSetup = false
    @State private var executingAction = false

    // Scene execution callback (set by parent)
    var onExecuteAction: ((VoiceCommandManager.VoiceAction) -> Void)?

    var body: some View {
        ZStack {
            Color.kachaBg.ignoresSafeArea()

            VStack(spacing: 32) {
                // Header
                HStack {
                    Text("音声コントロール")
                        .font(.title2).bold().foregroundColor(.white)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                // Waveform
                if voiceManager.isListening {
                    WaveformView(phase: wavePhase, amplitude: waveAmplitude)
                        .frame(height: 80)
                        .padding(.horizontal, 40)
                        .onAppear {
                            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                                wavePhase = .pi * 2
                            }
                            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                waveAmplitude = 0.7
                            }
                        }
                }

                // Status text
                if let action = voiceManager.matchedAction {
                    VStack(spacing: 12) {
                        Image(systemName: action.icon)
                            .font(.system(size: 48))
                            .foregroundColor(Color(hex: action.color))
                        Text(action.label)
                            .font(.title).bold().foregroundColor(.white)
                        if executingAction {
                            ProgressView()
                                .tint(Color(hex: action.color))
                                .scaleEffect(1.2)
                        } else {
                            Text("実行完了")
                                .font(.subheadline)
                                .foregroundColor(Color(hex: action.color))
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                } else if voiceManager.isListening {
                    VStack(spacing: 8) {
                        Text(voiceManager.lastTranscript.isEmpty ? "聞いています..." : voiceManager.lastTranscript)
                            .font(.title3).foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .animation(.easeInOut, value: voiceManager.lastTranscript)
                        Text("コマンドを話してください")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 32)
                } else if let error = voiceManager.errorMessage {
                    Text(error)
                        .font(.subheadline).foregroundColor(.kachaDanger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else {
                    VStack(spacing: 8) {
                        Text("マイクをタップして開始")
                            .font(.title3).foregroundColor(.white)
                        Text("「開けて」「おやすみ」「電気つけて」など")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Mic button
                Button {
                    Task { await toggleListening() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(voiceManager.isListening ? Color.kachaDanger.opacity(0.2) : Color.kacha.opacity(0.15))
                            .frame(width: 100, height: 100)

                        if voiceManager.isListening {
                            // Pulse ring
                            Circle()
                                .stroke(Color.kachaDanger.opacity(0.3), lineWidth: 3)
                                .frame(width: 120, height: 120)
                                .scaleEffect(voiceManager.isListening ? 1.2 : 1.0)
                                .opacity(voiceManager.isListening ? 0 : 1)
                                .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: voiceManager.isListening)
                        }

                        Image(systemName: voiceManager.isListening ? "stop.fill" : "mic.fill")
                            .font(.system(size: 36))
                            .foregroundColor(voiceManager.isListening ? .kachaDanger : .kacha)
                    }
                }
                .disabled(executingAction)

                // Voiceprint setup
                HStack(spacing: 16) {
                    if voiceManager.authSetupComplete {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.kachaSuccess)
                            Text("声紋登録済み")
                                .font(.caption).foregroundColor(.kachaSuccess)
                        }
                    }
                    Button {
                        showAuthSetup = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform.circle")
                            Text(voiceManager.authSetupComplete ? "再登録" : "声紋登録")
                        }
                        .font(.caption).foregroundColor(.kacha)
                    }
                }
                .padding(.bottom, 8)

                // Command list
                commandListSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .task {
            permissionsGranted = await voiceManager.requestPermissions()
        }
        .onChange(of: voiceManager.matchedAction) { _, action in
            if let action = action {
                executeAction(action)
            }
        }
        .sheet(isPresented: $showAuthSetup) {
            VoiceprintSetupView()
        }
    }

    // MARK: - Actions

    private func toggleListening() async {
        if voiceManager.isListening {
            voiceManager.stopListening()
        } else {
            guard permissionsGranted else {
                permissionsGranted = await voiceManager.requestPermissions()
                return
            }
            wavePhase = 0
            waveAmplitude = 0.3
            voiceManager.startListening()
        }
    }

    private func executeAction(_ action: VoiceCommandManager.VoiceAction) {
        executingAction = true
        onExecuteAction?(action)
        // Auto-dismiss after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            executingAction = false
        }
    }

    // MARK: - Command List

    private var commandListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("利用可能なコマンド")
                .font(.caption).bold().foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(VoiceCommandManager.VoiceAction.allCases, id: \.rawValue) { action in
                    HStack(spacing: 6) {
                        Image(systemName: action.icon)
                            .font(.caption)
                            .foregroundColor(Color(hex: action.color))
                            .frame(width: 16)
                        Text(action.label)
                            .font(.caption2).foregroundColor(.white.opacity(0.7))
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

// MARK: - Waveform View

struct WaveformView: View {
    let phase: Double
    let amplitude: Double

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let width = size.width
            let points = stride(from: 0.0, through: width, by: 2).map { x -> CGPoint in
                let relativeX = x / width
                let sine = sin(relativeX * Double.pi * 4.0 + phase)
                let envelope = sin(relativeX * .pi) // fade at edges
                let y = midY + sine * midY * amplitude * envelope
                return CGPoint(x: x, y: y)
            }

            var path = Path()
            if let first = points.first {
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }

            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [.kacha.opacity(0.3), .kacha, .kacha.opacity(0.3)]),
                    startPoint: CGPoint(x: 0, y: midY),
                    endPoint: CGPoint(x: width, y: midY)
                ),
                lineWidth: 2.5
            )
        }
    }
}

// MARK: - Voiceprint Setup View

struct VoiceprintSetupView: View {
    @StateObject private var voiceManager = VoiceCommandManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isRecording = false

    var body: some View {
        ZStack {
            Color.kachaBg.ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Text("声紋登録")
                        .font(.title2).bold().foregroundColor(.white)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.kacha)

                Text("「カギ」と3回話してください")
                    .font(.title3).foregroundColor(.white)

                Text("声の特徴を記録して認証に使用します")
                    .font(.caption).foregroundColor(.secondary)

                // Progress dots
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(index < voiceManager.authSamplesRecorded ? Color.kachaSuccess : Color.white.opacity(0.15))
                            .frame(width: 16, height: 16)
                            .overlay(
                                index < voiceManager.authSamplesRecorded
                                    ? Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                                    : nil
                            )
                    }
                }
                .padding(.top, 8)

                if let error = voiceManager.errorMessage {
                    Text(error)
                        .font(.caption).foregroundColor(.kachaDanger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                if voiceManager.authSetupComplete {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48)).foregroundColor(.kachaSuccess)
                        Text("声紋登録完了")
                            .font(.title3).bold().foregroundColor(.kachaSuccess)
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
                    }
                } else {
                    Button {
                        isRecording = true
                        voiceManager.startVoiceprintSample()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
                            isRecording = false
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(isRecording ? Color.kachaDanger.opacity(0.2) : Color.kacha.opacity(0.15))
                                .frame(width: 80, height: 80)
                            Image(systemName: isRecording ? "waveform" : "mic.fill")
                                .font(.system(size: 28))
                                .foregroundColor(isRecording ? .kachaDanger : .kacha)
                        }
                    }
                    .disabled(isRecording)

                    Text("サンプル \(voiceManager.authSamplesRecorded) / 3")
                        .font(.caption).foregroundColor(.secondary)
                }

                // Reset button
                if voiceManager.authSetupComplete || voiceManager.authSamplesRecorded > 0 {
                    Button("リセット") {
                        voiceManager.resetVoiceprint()
                    }
                    .font(.caption).foregroundColor(.kachaDanger)
                }

                Spacer()
            }
        }
    }
}

// MARK: - Floating Mic Button (for HomeView overlay)

struct FloatingMicButton: View {
    @Binding var showVoiceControl: Bool

    var body: some View {
        Button {
            showVoiceControl = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color.kacha)
                    .frame(width: 56, height: 56)
                    .shadow(color: .kacha.opacity(0.4), radius: 8, x: 0, y: 4)
                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.kachaBg)
            }
        }
    }
}
