//
//  RoomDetailViewModel.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 09/09/26.
//

import Foundation
import Observation

/// Loads a room's playable clips and groups them by capture hour.
@MainActor
@Observable
final class RoomDetailViewModel {

    private(set) var hourlyGroups: [HourlyClipGroup] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// The most recent clip uploaded by `authorName`, if any. Optionally
    /// restricted to a pre-filtered clip list (e.g. the current hour's).
    func latestClip(by authorName: String, in clips: [PlaybackClip]? = nil) -> PlaybackClip? {
        (clips ?? hourlyGroups.flatMap(\.clips))
            .filter { $0.authorName == authorName }
            .max { $0.createdAt < $1.createdAt }
    }

    /// Surfaces a message in the view's error banner.
    func report(_ message: String) {
        errorMessage = message
    }

    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = AppDependencies.apiClient) {
        self.apiClient = apiClient
    }

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

    /// Request body for `POST /api/logs/delete`.
    private struct DeleteLogRequest: Encodable {
        let roomId: UUID
        let s3Key: String
    }

    /// Deletes one of the user's own clips; returns whether it succeeded.
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

    /// Request body for `PATCH /api/rooms/:id`.
    private struct UpdateRoomRequest: Encodable {
        let name: String?
        let maxMembers: Int?
    }

    /// Updates the room's name and/or size; returns the refreshed room.
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
