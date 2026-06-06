import SwiftUI
import SwiftData

@main
struct TrellisStudioApp: App {
    @StateObject private var onboardingService = OnboardingService.shared
    
    var body: some Scene {
        WindowGroup {
            if onboardingService.isCompleted {
                ContentView()
            } else {
                OnboardingView()
            }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

