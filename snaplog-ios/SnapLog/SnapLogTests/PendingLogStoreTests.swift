//
//  PendingLogStoreTests.swift
//  SnapLogTests
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Testing
import Foundation
@testable import SnapLog

@MainActor
struct PendingLogStoreTests {

    @Test func enqueueAndFetchKeepsInsertionOrder() {
        let store = PendingLogStore(inMemory: true)
        let urlA = FileManager.default.temporaryDirectory.appendingPathComponent("a.mp4")
        let urlB = FileManager.default.temporaryDirectory.appendingPathComponent("b.mp4")

        store.enqueue(localFileURL: urlA, roomID: "r1")
        store.enqueue(localFileURL: urlB, roomID: "r2")

        let pending = store.pending()
        #expect(pending.count == 2)
        #expect(pending[0].roomID == "r1")
        #expect(pending[1].roomID == "r2")
    }

    @Test func removeDeletesBufferedLog() {
        let store = PendingLogStore(inMemory: true)
        store.enqueue(
            localFileURL: FileManager.default.temporaryDirectory.appendingPathComponent("c.mp4"),
            roomID: "r1"
        )

        let first = store.pending()
        #expect(first.count == 1)
        store.remove(first[0])

        #expect(store.pending().isEmpty)
    }

    @Test func pruneDropsLogsWithMissingFiles() throws {
        let store = PendingLogStore(inMemory: true)
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).mp4")
        let existingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("existing-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: existingURL.path, contents: Data([0]))
        defer { try? FileManager.default.removeItem(at: existingURL) }

        store.enqueue(localFileURL: missingURL, roomID: "r-missing")
        store.enqueue(localFileURL: existingURL, roomID: "r-existing")

        store.pruneMissingFiles()

        let remaining = store.pending()
        #expect(remaining.count == 1)
        #expect(remaining[0].roomID == "r-existing")
    }
}
