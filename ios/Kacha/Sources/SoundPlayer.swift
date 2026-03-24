import AVFoundation

class SoundPlayer {
    static let shared = SoundPlayer()
    private var player: AVAudioPlayer?

    private init() {}

    func playKacha() {
        guard let url = Bundle.main.url(forResource: "kacha", withExtension: "wav") else {
            // Sound file not present — silently skip
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            // Silently ignore audio errors
        }
    }
}
