import SwiftUI

/// A view that manages a queue of images for batch 3D generation.
///
/// Use `BatchQueueView` to allow users to drop multiple images and process them
/// sequentially using the pipeline.
struct BatchQueueView: View {
    @State private var queue: [String] = []
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Batch Queue")
                .font(.headline)
            
            if queue.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.slateGray)
                    Text("Drag multiple images here to queue them")
                        .foregroundColor(Theme.slateGray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(queue, id: \.self) { item in
                    Text(item)
                }
            }
            
            HStack {
                Button("Pause All") {
                    // Pause batch processing
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(Theme.CornerRadius.button)
                
                Spacer()
                
                Button("Clear") {
                    queue.removeAll()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(Theme.CornerRadius.button)
                .foregroundColor(Theme.errorRed)
            }
        }
        .padding(24)
        .background(Theme.background)
        .cornerRadius(Theme.CornerRadius.panel)
    }
}
