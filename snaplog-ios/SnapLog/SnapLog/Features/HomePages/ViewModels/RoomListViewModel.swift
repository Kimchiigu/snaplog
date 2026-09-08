//
//  RoomListViewModel.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation
import Observation

/// Loads the room feed, tracks live presence, and drives room creation/joining.
@MainActor
@Observable
final class RoomListViewModel {

    private(set) var rooms: [Room] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Room IDs in which at least one member is currently recording.
    private(set) var recordingRoomIDs: Set<String> = []

    private let apiClient: APIClientProtocol
    private let analytics: AnalyticsService
    private let socket: WebSocketManager
    private var presenceTask: Task<Void, Never>?

    init(
        apiClient: APIClientProtocol,
        analytics: AnalyticsService = NoopAnalyticsService(),
        socket: WebSocketManager = AppDependencies.presenceSocket
    ) {
        self.apiClient = apiClient
        self.analytics = analytics
        self.socket = socket
    }

    // MARK: - Feed

    func loadRooms() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: RoomListResponse = try await apiClient.request(path: "/rooms", method: .get)
            rooms = response.rooms
        } catch {
            errorMessage = "Couldn't load your rooms. Pull to refresh."
        }
    }

    // MARK: - Presence

    func startObservingPresence() {
        socket.connect()
        presenceTask?.cancel()
        presenceTask = Task { [weak self] in
            guard let events = self?.socket.events else { return }
            for await event in events {
                await self?.handle(event)
            }
        }
    }

    func stopObservingPresence() {
        presenceTask?.cancel()
        presenceTask = nil
        socket.disconnect()
    }

    private func handle(_ event: PresenceEvent) {
        switch event {
        case .memberStartedRecording(let roomID, _):
            recordingRoomIDs.insert(roomID)
        case .memberStoppedRecording(let roomID, _):
            recordingRoomIDs.remove(roomID)
        case .connected, .disconnected:
            break
        }
    }

    // MARK: - Create / Join

    func createRoom(named name: String, roomType: RoomType) async -> Bool {
        do {
            let room: Room = try await apiClient.request(
                path: "/rooms", method: .post, body: CreateRoomRequest(name: name, roomType: roomType)
            )
            rooms.append(room)
            analytics.track(event: "room_created", properties: ["room_type": roomType.rawValue])
            return true
        } catch {
            errorMessage = "Couldn't create the room. Please try again."
            return false
        }
    }

    func joinRoom(code: String) async -> Bool {
        do {
            let room: Room = try await apiClient.request(
                path: "/rooms/join", method: .post, body: JoinRoomRequest(code: code)
            )
            guard !rooms.contains(where: { $0.id == room.id }) else { return true }
            rooms.append(room)
            analytics.track(event: "room_joined", properties: [:])
            return true
        } catch {
            errorMessage = "Couldn't join that room. Check the code and try again."
            return false
        }
    }

    /// Whether the room should render as a 2x2 grid.
    func usesGridLayout(for room: Room) -> Bool {
        room.roomType == .grid
    }
}
