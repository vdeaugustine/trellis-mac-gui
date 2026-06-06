import SwiftUI

struct WatchdogErrorSheet: View {
    @Environment(\.dismiss) var dismiss
    
    var onRetry: () -> Void
    var onOpenSettings: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(Theme.warningAmber)
                    .pulse()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Metal GPU Watchdog Interrupted")
                        .font(.title2).bold()
                    Text("The macOS GPU watchdog killed the Metal kernel during generation.")
                        .font(.subheadline)
                        .foregroundColor(Theme.slateGray)
                }
            }
            .padding(.top, 10)
            
            // Workarounds
            VStack(alignment: .leading, spacing: 16) {
                Text("Workarounds to prevent this:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 12) {
                    workaroundRow(
                        num: "1",
                        title: "Reduce WindowServer Load",
                        desc: "Close the MacBook lid or unplug external 4K/5K displays, and run headless. The watchdog is highly sensitive to active display output."
                    )
                    
                    Divider()
                    
                    workaroundRow(
                        num: "2",
                        title: "Extend Metal Timeout (MTL_CAPTURE_ENABLED)",
                        desc: "Enable Metal Capturing in Advanced Settings. This extends the timeout threshold on Apple Silicon as a side effect of debugging mode."
                    )
                    
                    Divider()
                    
                    workaroundRow(
                        num: "3",
                        title: "Use Fallback Backend (SPARSE_CONV_BACKEND)",
                        desc: "Set the sparse convolution backend to 'none' in Advanced Settings. This is slower but avoids heavy Metal dispatches."
                    )
                }
                .padding(16)
                .background(Color.white.opacity(0.02))
                .cornerRadius(Theme.CornerRadius.card)
                .border(Theme.border, width: 1)
            }
            
            // Buttons
            HStack(spacing: 16) {
                Button("Open Settings") {
                    dismiss()
                    onOpenSettings()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(Theme.CornerRadius.button)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(Theme.CornerRadius.button)
                
                Button("Retry Generation") {
                    dismiss()
                    onRetry()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Theme.accentGradient)
                .foregroundColor(.white)
                .cornerRadius(Theme.CornerRadius.button)
            }
        }
        .padding(32)
        .frame(width: 550)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
    
    private func workaroundRow(num: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(num)
                .font(.system(.body, design: .rounded))
                .bold()
                .foregroundColor(Theme.accentIndigo)
                .frame(width: 20, height: 20)
                .background(Theme.accentIndigo.opacity(0.15))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline).bold()
                Text(desc)
                    .font(.caption)
                    .foregroundColor(Theme.slateGray)
                    .lineSpacing(2)
            }
        }
    }
}
