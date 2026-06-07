import SwiftUI

struct SidebarView: View {
    @Binding var selectedItem: String?
    @State private var searchText = ""
    @State private var isBatchMode = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                Button(action: {
                    // Start new generation
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("New Generation")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.accentGradient)
                    .foregroundColor(.white)
                    .cornerRadius(Theme.CornerRadius.button)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.newGenerationButton)
                
                HStack {
                    Text("Batch Mode")
                        .font(.subheadline)
                    Spacer()
                    Toggle("", isOn: $isBatchMode)
                        .toggleStyle(.switch)
                        .accessibilityIdentifier(AccessibilityID.batchModeToggle)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.02))
            
            Divider()
            
            // Search
            TextField("Search history...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(12)
                .accessibilityIdentifier(AccessibilityID.searchField)
            
            // History List
            List(selection: $selectedItem) {
                Text("Today")
                    .font(.caption)
                    .foregroundColor(Theme.slateGray)
                    .listRowBackground(Color.clear)
                
                // Placeholder rows
                HistoryRowView(title: "chair_concept.png", status: .complete, timeAgo: "10m ago")
                    .tag("1")
                HistoryRowView(title: "character_sketch.jpg", status: .complete, timeAgo: "2h ago")
                    .tag("2")
                HistoryRowView(title: "car_profile.png", status: .failed, timeAgo: "1d ago")
                    .tag("3")
            }
            .listStyle(.sidebar)
            .background(Theme.background)
        }
        .background(Theme.background)
    }
}

struct HistoryRowView: View {
    var title: String
    var status: GenerationStatusMock
    var timeAgo: String
    
    enum GenerationStatusMock {
        case complete, generating, failed
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail placeholder
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.1))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.white.opacity(0.4))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.subheadline)
                
                HStack {
                    statusIcon
                    Text(timeAgo)
                        .font(.caption)
                        .foregroundColor(Theme.slateGray)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    var statusIcon: some View {
        switch status {
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Theme.successGreen)
                .font(.system(size: 10))
        case .generating:
            Image(systemName: "hourglass.circle.fill")
                .foregroundColor(Theme.warningAmber)
                .font(.system(size: 10))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(Theme.errorRed)
                .font(.system(size: 10))
        }
    }
}
