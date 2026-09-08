//
//  RoomListViewModelTests.swift
//  SnapLogTests
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Testing
@testable import SnapLog

@MainActor
struct RoomListViewModelTests {

    private func makeRoom(_ id: String, type: RoomType = .grid) -> Room {
        Room(id: id, name: "Room \(id)", roomType: type, memberCount: 2, joinCode: nil)
    }

    @Test func loadRoomsPopulatesFeed() async {
        let api = MockAPIClient()
        let rooms = [makeRoom("1"), makeRoom("2", type: .stack)]
        api.stub("/rooms", result: .success(RoomListResponse(rooms: rooms)))
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

    @Test func createRoomAppendsAndReturnsTrue() async {
        let api = MockAPIClient()
        let room = makeRoom("new")
        api.stub("/rooms", result: .success(room))
        let viewModel = RoomListViewModel(apiClient: api)

        let created = await viewModel.createRoom(named: "Trip", roomType: .grid)

        #expect(created)
        #expect(viewModel.rooms == [room])
        #expect(api.recordedCalls.contains { $0.path == "/rooms" && $0.method == .post })
    }

    @Test func joinRoomAppendsAndReturnsTrue() async {
        let api = MockAPIClient()
        let room = makeRoom("joined")
        api.stub("/rooms/join", result: .success(room))
        let viewModel = RoomListViewModel(apiClient: api)

        let joined = await viewModel.joinRoom(code: "AB12")

        #expect(joined)
        #expect(viewModel.rooms == [room])
    }

    @Test func joinRoomDoesNotDuplicateExistingRoom() async {
        let api = MockAPIClient()
        let room = makeRoom("dup")
        api.stub("/rooms", result: .success(RoomListResponse(rooms: [room])))
        api.stub("/rooms/join", result: .success(room))
        let viewModel = RoomListViewModel(apiClient: api)
        await viewModel.loadRooms()

        let joined = await viewModel.joinRoom(code: "AB12")

        #expect(joined)
        #expect(viewModel.rooms.count == 1)
    }

    @Test func gridLayoutDependsOnRoomType() {
        let viewModel = RoomListViewModel(apiClient: MockAPIClient())

        #expect(viewModel.usesGridLayout(for: makeRoom("g", type: .grid)))
        #expect(!viewModel.usesGridLayout(for: makeRoom("s", type: .stack)))
    }
}
