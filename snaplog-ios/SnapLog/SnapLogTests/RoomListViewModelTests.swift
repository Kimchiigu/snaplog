//
//  RoomListViewModelTests.swift
//  SnapLogTests
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation
import Testing
@testable import SnapLog

@MainActor
struct RoomListViewModelTests {

    private func makeRoom(_ id: String, type: RoomType = .log) -> Room {
        Room(
            id: UUID(uuidString: id) ?? UUID(),
            name: "Room \(id)",
            roomType: type,
            maxMembers: 4,
            inviteCode: "AB12CD",
            createdAt: nil,
            members: [],
            timeline: []
        )
    }

    @Test func loadRoomsPopulatesFeed() async {
        let api = MockAPIClient()
        let rooms = [makeRoom("00000000-0000-0000-0000-000000000001"),
                     makeRoom("00000000-0000-0000-0000-000000000002", type: .stack)]
        // The backend returns a bare array, not an envelope.
        api.stub("/rooms", result: .success(rooms))
        let viewModel = RoomListViewModel(apiClient: api)

        await viewModel.loadRooms()

        #expect(viewModel.rooms == rooms)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func loadRoomsFailureSetsErrorMessage() async {
        let api = MockAPIClient()
        api.stubFailure("/rooms", APIError.network(underlying: "offline"))
        let viewModel = RoomListViewModel(apiClient: api)

        await viewModel.loadRooms()

        #expect(viewModel.rooms.isEmpty)
        #expect(viewModel.errorMessage != nil)
    }

    @Test func createRoomSendsMaxMembersAndAppends() async {
        let api = MockAPIClient()
        let room = makeRoom("00000000-0000-0000-0000-000000000003")
        api.stub("/rooms", result: .success(room))
        let viewModel = RoomListViewModel(apiClient: api)

        let created = await viewModel.createRoom(named: "Trip", roomType: .log, maxMembers: 4)

        #expect(created)
        #expect(viewModel.rooms == [room])
        #expect(api.recordedCalls.contains { $0.path == "/rooms" && $0.method == .post })
    }

    @Test func joinRoomAppendsAndReturnsTrue() async {
        let api = MockAPIClient()
        let room = makeRoom("00000000-0000-0000-0000-000000000004")
        api.stub("/rooms/join", result: .success(room))
        let viewModel = RoomListViewModel(apiClient: api)

        let joined = await viewModel.joinRoom(inviteCode: "AB12CD")

        #expect(joined)
        #expect(viewModel.rooms == [room])
    }

    @Test func joinRoomDoesNotDuplicateExistingRoom() async {
        let api = MockAPIClient()
        let room = makeRoom("00000000-0000-0000-0000-000000000005")
        api.stub("/rooms", result: .success([room]))
        api.stub("/rooms/join", result: .success(room))
        let viewModel = RoomListViewModel(apiClient: api)
        await viewModel.loadRooms()

        let joined = await viewModel.joinRoom(inviteCode: "AB12CD")

        #expect(joined)
        #expect(viewModel.rooms.count == 1)
    }

    @Test func joinRoomMapsBackendErrorsToFriendlyMessages() async {
        let api = MockAPIClient()
        api.stubFailure("/rooms/join", APIError.httpStatus(409))
        let viewModel = RoomListViewModel(apiClient: api)

        let joined = await viewModel.joinRoom(inviteCode: "AB12CD")

        #expect(!joined)
        #expect(viewModel.errorMessage == "You're already a member of that room.")
    }

    @Test func gridLayoutDependsOnRoomType() {
        let viewModel = RoomListViewModel(apiClient: MockAPIClient())

        #expect(viewModel.usesGridLayout(for: makeRoom("00000000-0000-0000-0000-000000000006", type: .log)))
        #expect(!viewModel.usesGridLayout(for: makeRoom("00000000-0000-0000-0000-000000000007", type: .stack)))
    }
}
