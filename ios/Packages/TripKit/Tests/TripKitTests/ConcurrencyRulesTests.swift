import Testing

/// TripKit keeps the app's concurrency rules (`Package.swift`): a `nonisolated async` function runs on
/// the actor of whoever calls it, and only one marked `@concurrent` leaves it. Without the package's
/// `NonisolatedNonsendingByDefault`, the same code would run on the global executor here and on the
/// caller's actor in the app.
@MainActor @Suite struct ConcurrencyRulesTests {
    nonisolated func isolationOfPlainAsync() async -> (any Actor)? { #isolation }

    @concurrent nonisolated func isolationOfConcurrent() async -> (any Actor)? { #isolation }

    @Test func plainNonisolatedAsyncRunsOnTheCallersActor() async {
        #expect(await isolationOfPlainAsync() === MainActor.shared)
    }

    @Test func concurrentLeavesTheCallersActor() async {
        #expect(await isolationOfConcurrent() == nil)
    }
}
