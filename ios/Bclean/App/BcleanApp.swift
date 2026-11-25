import SwiftUI

@main
struct BcleanApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var store = StoreManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(store)
                .tint(Theme.accent)
                .onAppear { Analytics.log("app_open") }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        library.refreshAuth()
                        library.refreshDeviceStorage()
                    }
                }
        }
    }
}
