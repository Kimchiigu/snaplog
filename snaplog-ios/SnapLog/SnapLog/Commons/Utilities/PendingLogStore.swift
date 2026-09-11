import Foundation
import SwiftData

@MainActor
final class PendingLogStore {

    private let container: ModelContainer

    init(inMemory: Bool = false) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: PendingLog.self, configurations: configuration)
        } catch {
            fatalError("Could not create PendingLog container: \(error)")
        }
    }

    func enqueue(localFileURL: URL, roomID: String) {
        let context = container.mainContext
        context.insert(PendingLog(localFileURL: localFileURL, roomID: roomID))
        try? context.save()
    }

    func pending() -> [PendingLog] {
        let context = container.mainContext
        let descriptor = FetchDescriptor<PendingLog>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func remove(_ log: PendingLog) {
        let context = container.mainContext
        context.delete(log)
        try? context.save()
    }

    func pruneMissingFiles() {
        for log in pending() where !FileManager.default.fileExists(atPath: log.localFileURL.path) {
            remove(log)
        }
    }
}
