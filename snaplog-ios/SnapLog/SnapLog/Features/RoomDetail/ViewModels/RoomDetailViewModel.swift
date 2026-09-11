import Foundation
import Observation

@MainActor
@Observable
final class RoomDetailViewModel {

    private(set) var hourlyGroups: [HourlyClipGroup] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private(set) var liveRoom: Room?

    private let socket: WebSocketManager
    private var presenceTask: Task<Void, Never>?

    init(
        apiClient: APIClientProtocol = AppDependencies.apiClient,
        socket: WebSocketManager = AppDependencies.presenceSocket
    ) {
        self.apiClient = apiClient
        self.socket = socket
    }

    func latestClip(by authorName: String, in clips: [PlaybackClip]? = nil) -> PlaybackClip? {
        (clips ?? hourlyGroups.flatMap(\.clips))
            .filter { $0.authorName == authorName }
            .max { $0.createdAt < $1.createdAt }
    }

    func report(_ message: String) {
        errorMessage = message
    }

    private let apiClient: APIClientProtocol

    func loadPlayback(roomID: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let clips: [PlaybackClip] = try await apiClient.request(
                path: "/rooms/\(roomID.uuidString)/playback",
                method: .get
            )
            hourlyGroups = ClipGrouper.groupByHour(clips)
        } catch {
            errorMessage = "Couldn't load this room's clips."
        }
    }

    func fetchRoom(roomID: UUID) async {
        if let room: Room = try? await apiClient.request(
            path: "/rooms/\(roomID.uuidString)",
            method: .get
        ) {
            liveRoom = room
        }
    }

    func startObservingPresence(roomID: UUID) {
        presenceTask?.cancel()
        presenceTask = Task { [weak self] in
            for await event in self?.socket.events ?? AsyncStream { $0.finish() } {
                guard let self else { return }
                switch event {
                case .memberJoined(let id) where UUID(uuidString: id) == roomID:
                    await self.fetchRoom(roomID: roomID)
                case .newLog(let id, _), .logDeleted(let id), .newDigestReady(let id)
                    where UUID(uuidString: id) == roomID:
                    await self.loadPlayback(roomID: roomID)
                default:
                    break
                }
            }
        }
    }

    func stopObservingPresence() {
        presenceTask?.cancel()
        presenceTask = nil
    }

    private struct DeleteLogRequest: Encodable {
        let roomId: UUID
        let s3Key: String
    }

    func deleteClip(roomID: UUID, s3Key: String) async -> Bool {
        do {
            try await apiClient.requestVoid(
                path: "/logs/delete",
                method: .post,
                body: DeleteLogRequest(roomId: roomID, s3Key: s3Key)
            )
            return true
        } catch {
            errorMessage = "Couldn't delete the clip."
            return false
        }
    }

    private struct UpdateRoomRequest: Encodable {
        let name: String?
        let maxMembers: Int?
    }

    func deleteRoom(roomID: UUID) async -> Bool {
        do {
            try await apiClient.requestVoid(
                path: "/rooms/\(roomID.uuidString)",
                method: .delete,
                body: Optional<Int>.none
            )
            return true
        } catch {
            errorMessage = "Couldn't delete the room."
            return false
        }
    }

    func leaveRoom(roomID: UUID) async -> Bool {
        do {
            try await apiClient.requestVoid(
                path: "/rooms/\(roomID.uuidString)/leave",
                method: .post,
                body: Optional<Int>.none
            )
            return true
        } catch {
            errorMessage = "Couldn't leave the room."
            return false
        }
    }

    func updateRoom(roomID: UUID, name: String?, maxMembers: Int?) async -> Room? {
        do {
            return try await apiClient.request(
                path: "/rooms/\(roomID.uuidString)",
                method: .patch,
                body: UpdateRoomRequest(name: name, maxMembers: maxMembers)
            )
        } catch {
            errorMessage = "Couldn't update the room."
            return nil
        }
    }
}
