import SwiftData
import Foundation

/// Background-safe persistence actor for ConnectivityEvent records.
///
/// Uses `@ModelActor` to create an isolated ModelContext for background writes.
/// This actor must be instantiated ONCE per ModelContainer and reused -- do NOT
/// create a new EventStore per call. Each init creates a fresh ModelContext, and
/// multiple contexts writing to the same store can cause conflicts.
///
/// The singleton pattern will be enforced in Phase 2 when the monitoring
/// coordinator is built. For now, callers are responsible for reusing instances.
///
/// All predicate filters use raw Int values (e.g., `eventTypeRaw`) instead of
/// enum types, because SwiftData does not support enum predicates as of iOS 18+.
@ModelActor
actor EventStore {

    // MARK: - Insert

    /// Inserts a new connectivity event and saves immediately.
    /// - Parameter event: The ConnectivityEvent to persist.
    /// - Throws: SwiftData persistence errors.
    func insertEvent(_ event: ConnectivityEvent) throws {
        modelContext.insert(event)
        try modelContext.save()
    }

    // MARK: - Fetch

    /// Fetches the most recent events, ordered by timestamp descending.
    /// - Parameter limit: Maximum number of events to return. Defaults to 100.
    /// - Returns: Array of ConnectivityEvent ordered newest-first.
    func fetchEvents(limit: Int = 100) throws -> [ConnectivityEvent] {
        var descriptor = FetchDescriptor<ConnectivityEvent>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    /// Fetches all events since the given date, ordered by timestamp descending.
    /// - Parameter date: The earliest timestamp to include.
    /// - Returns: Array of ConnectivityEvent since `date`, ordered newest-first.
    func fetchEvents(since date: Date) throws -> [ConnectivityEvent] {
        let descriptor = FetchDescriptor<ConnectivityEvent>(
            predicate: #Predicate { $0.timestamp >= date },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Count

    /// Returns the total number of stored events.
    func countEvents() throws -> Int {
        let descriptor = FetchDescriptor<ConnectivityEvent>()
        return try modelContext.fetchCount(descriptor)
    }

    /// Returns the count of events matching a specific event type raw value.
    ///
    /// Uses `eventTypeRaw` (Int) instead of the `EventType` enum because
    /// SwiftData does not support enum types in `#Predicate` queries.
    ///
    /// - Parameter eventTypeRaw: The raw Int value of the EventType to count.
    /// - Returns: Number of events of the specified type.
    func countEvents(ofType eventTypeRaw: Int) throws -> Int {
        let descriptor = FetchDescriptor<ConnectivityEvent>(
            predicate: #Predicate { $0.eventTypeRaw == eventTypeRaw }
        )
        return try modelContext.fetchCount(descriptor)
    }

    // MARK: - Delete

    /// Deletes all stored events and saves immediately.
    /// - Throws: SwiftData persistence errors.
    func deleteAllEvents() throws {
        try modelContext.delete(model: ConnectivityEvent.self)
        try modelContext.save()
    }
}
