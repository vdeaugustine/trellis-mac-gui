import SwiftUI

extension Animation {
    static var panelSpring: Animation {
        .spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0)
    }
    
    static var smoothSpring: Animation {
        .spring(response: 0.35, dampingFraction: 0.76, blendDuration: 0)
    }
}

struct PulseModifier: ViewModifier {
    @State private var isAnimating = false
    let speed: Double
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isAnimating ? 1.08 : 0.96)
            .opacity(isAnimating ? 0.9 : 0.5)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: speed).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .white.opacity(0.18), .clear]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .offset(x: -geo.size.width + (phase * geo.size.width * 2))
                    .onAppear {
                        withAnimation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            phase = 1
                        }
                    }
                }
            )
            .mask(content)
    }
}

extension View {
    func pulse(speed: Double = 1.0) -> some View {
        modifier(PulseModifier(speed: speed))
    }
    
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
