import SwiftUI

struct DoorOpenEffect: View {
    let guestName: String
    let onDismiss: () -> Void

    @State private var doorAngle: Double = 0
    @State private var particles: [Particle] = []
    @State private var opacity: Double = 1
    @State private var scale: Double = 0.8

    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var velocityX: CGFloat
        var velocityY: CGFloat
        var color: Color
        var size: CGFloat
        var opacity: Double = 1
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 24) {
                // Door animation
                ZStack {
                    // Door frame
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.kacha.opacity(0.2))
                        .frame(width: 100, height: 160)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.kacha, lineWidth: 2)
                        )

                    // Door panel (opening)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "1A1A2E"))
                        .frame(width: 94, height: 154)
                        .rotation3DEffect(
                            .degrees(doorAngle),
                            axis: (x: 0, y: 1, z: 0),
                            anchor: .leading,
                            perspective: 0.5
                        )
                        .overlay(
                            // Door handle
                            Circle()
                                .fill(Color.kacha)
                                .frame(width: 10, height: 10)
                                .offset(x: 30, y: 0)
                                .opacity(1 - doorAngle / 80)
                        )

                    // Sunburst when open
                    if doorAngle > 40 {
                        RadialGradient(
                            colors: [Color.kacha.opacity(0.6), Color.clear],
                            center: .leading,
                            startRadius: 0,
                            endRadius: 80
                        )
                        .frame(width: 160, height: 160)
                        .opacity((doorAngle - 40) / 40)
                    }
                }
                .frame(width: 160, height: 160)

                // Particles
                ForEach(particles) { p in
                    Circle()
                        .fill(p.color)
                        .frame(width: p.size, height: p.size)
                        .position(x: p.x, y: p.y)
                        .opacity(p.opacity)
                }

                VStack(spacing: 8) {
                    Text("ようこそ！")
                        .font(.title).bold()
                        .foregroundColor(.kacha)

                    Text(guestName + " 様")
                        .font(.title2)
                        .foregroundColor(.white)

                    Text("チェックインしました")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear { animate() }
    }

    private func animate() {
        // Door open animation
        withAnimation(.easeOut(duration: 0.8)) {
            doorAngle = -70
            scale = 1.0
        }

        // Spawn confetti particles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            spawnParticles()
        }

        // Auto-dismiss after 2.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            dismiss()
        }
    }

    private func spawnParticles() {
        let colors: [Color] = [.kacha, .kachaAccent, .kachaSuccess, .white, Color(hex: "FFD700")]
        particles = (0..<20).map { _ in
            Particle(
                x: CGFloat.random(in: 60...300),
                y: CGFloat.random(in: 100...350),
                velocityX: CGFloat.random(in: -80...80),
                velocityY: CGFloat.random(in: -120...(-30)),
                color: colors.randomElement() ?? .kacha,
                size: CGFloat.random(in: 4...10)
            )
        }

        withAnimation(.easeOut(duration: 1.2)) {
            particles = particles.map { p in
                var updated = p
                updated.x += p.velocityX
                updated.y += p.velocityY
                updated.opacity = 0
                return updated
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.3)) {
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}
