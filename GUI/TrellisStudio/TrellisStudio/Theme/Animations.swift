import SwiftUI

extension Animation {
    /// A bouncy spring animation used for panel transitions.
    static var panelSpring: Animation {
        .spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0)
    }
    
    /// A smooth spring animation used for general UI state changes.
    static var smoothSpring: Animation {
        .spring(response: 0.35, dampingFraction: 0.76, blendDuration: 0)
    }
}

/// A view modifier that applies a continuous pulsing animation.
///
/// Use this modifier to draw attention to loading states or active indicators.
struct PulseModifier: ViewModifier {
    @State private var isAnimating = false
    
    /// The duration of a single pulse cycle.
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

/// A view modifier that applies a continuous metallic shimmer effect.
///
/// Use this modifier to indicate loading or placeholder states for content.
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
    /// Applies a continuous pulsing animation to the view.
    ///
    /// - Parameter speed: The duration of a single pulse cycle. Defaults to `1.0`.
    /// - Returns: A view that pulses continuously.
    func pulse(speed: Double = 1.0) -> some View {
        modifier(PulseModifier(speed: speed))
    }
    
    /// Applies a continuous metallic shimmer effect to the view.
    ///
    /// - Returns: A view that shimmers continuously.
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
