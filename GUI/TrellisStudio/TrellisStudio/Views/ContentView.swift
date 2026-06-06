import SwiftUI

struct ContentView: View {
    @State private var selectedItem: String?
    
    var body: some View {
        NavigationSplitView {
            SidebarView(selectedItem: $selectedItem)
                .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 320)
        } detail: {
            MainWorkspaceView()
        }
        //.toolbar {
            // ToolbarItems like Daemon status could go here
        //}
    }
}

struct MainWorkspaceView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                InputPanel()
                    .frame(maxWidth: .infinity)
                
                ParameterPanel()
                    .frame(width: 320)
            }
            .padding(24)
            
            Divider()
            
            ModelViewerPanel()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}
