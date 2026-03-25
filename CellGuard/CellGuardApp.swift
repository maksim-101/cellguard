import SwiftUI
import SwiftData

@main
struct CellGuardApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: ConnectivityEvent.self)
    }
}
