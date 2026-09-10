
import Foundation
import Observation

@MainActor
@Observable
final class RoomListViewModel {

    private(set) var rooms: [Room] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private(set) var freshRoomIDs: Set<UUID> = []

    struct NewLogNotice: Equatable {
        let roomID: UUID
        let roomName: String
        let authorName: String
    }
    private(set) var newLogNotice: NewLogNotice?

    struct NotificationItem: Identifiable, Equatable {
        let id = UUID()
        let roomID: UUID
        let roomName: String
        let authorName: String
        let receivedAt: Date
    }
    private(set) var notifications: [NotificationItem] = []

    var unreadNotificationCount: Int { notifications.count }

    var currentUserName: String?

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

    func loadRooms() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            rooms = try await apiClient.request(path: "/rooms", method: .get)
        } catch {
            errorMessage = "Couldn't load your rooms. Pull to refresh."
        }
    }

    func startObservingPresence(token: String) {
        socket.connect(token: token)
        presenceTask?.cancel()
        presenceTask = Task { [weak self] in
            guard let events = self?.socket.events else { return }
            for await event in events {
                self?.handle(event)
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
        case .newDigestReady(let roomID):
            guard let uuid = UUID(uuidString: roomID) else { return }
            freshRoomIDs.insert(uuid)
        case .newLog(let roomID, let authorName):
            guard let uuid = UUID(uuidString: roomID) else { return }
            Task {
                await loadRooms()
                guard let authorName, authorName != self.currentUserName,
                      let room = self.rooms.first(where: { $0.id == uuid }) else { return }
                PushService.shared.notifyNewLog(author: authorName, room: room.displayName)
                self.notifications.insert(
                    NotificationItem(
                        roomID: uuid,
                        roomName: room.displayName,
                        authorName: authorName,
                        receivedAt: Date()
                    ),
                    at: 0
                )
                self.newLogNotice = NewLogNotice(
                    roomID: uuid,
                    roomName: room.displayName,
                    authorName: authorName
                )
            }
        case .memberJoined:
            Task { await loadRooms() }
        case .logDeleted:
            Task { await loadRooms() }
        case .connected, .disconnected:
            break
        }
    }

    func dismissNotice() {
        newLogNotice = nil
    }

    /// Hands the unread items to the bell sheet and clears the badge.
    func takeNotifications() -> [NotificationItem] {
        let items = notifications
        notifications = []
        return items
    }

    func createRoom(named name: String, roomType: RoomType, maxMembers: Int) async -> Bool {
        do {
            let room: Room = try await apiClient.request(
                path: "/rooms",
                method: .post,
                body: CreateRoomRequest(name: name, roomType: roomType, maxMembers: maxMembers)
            )
            rooms.append(room)
            analytics.track(event: "room_created", properties: ["room_type": roomType.rawValue])
            return true
        } catch {
            errorMessage = Self.describe(error)
            return false
        }
    }

    func joinRoom(inviteCode: String) async -> Bool {
        do {
            let room: Room = try await apiClient.request(
                path: "/rooms/join", method: .post, body: JoinRoomRequest(inviteCode: inviteCode)
            )
            guard !rooms.contains(where: { $0.id == room.id }) else { return true }
            rooms.append(room)
            analytics.track(event: "room_joined", properties: [:])
            return true
        } catch {
            errorMessage = Self.describe(error)
            return false
        }
    }

    func usesGridLayout(for room: Room) -> Bool {
        room.roomType != .stack
    }

    static func describe(_ error: Error) -> String {
        guard let apiError = error as? APIError else {
            return "Something went wrong. Please try again."
        }
        switch apiError {
        case .httpStatus(404):
            return "No room found for that invite code."
        case .httpStatus(409):
            return "You're already a member of that room."
        case .httpStatus(403):
            return "That room is full."
        default:
            return "Something went wrong. Please try again."
        }
    }
}
