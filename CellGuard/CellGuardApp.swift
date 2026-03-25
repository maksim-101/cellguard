import SwiftUI
import SwiftData

@main
struct CellGuardApp: App {
    let container: ModelContainer
    @State private var monitor: ConnectivityMonitor

    init() {
        let container = try! ModelContainer(for: ConnectivityEvent.self)
        self.container = container
        let store = EventStore(modelContainer: container)
        _monitor = State(initialValue: ConnectivityMonitor(eventStore: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(monitor)
        }
        .modelContainer(container)
    }
}
