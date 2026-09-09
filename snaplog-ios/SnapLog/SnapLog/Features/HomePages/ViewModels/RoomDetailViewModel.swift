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

    /// The most recent clip uploaded by `authorName`, if any.
    func latestClip(by authorName: String) -> PlaybackClip? {
        hourlyGroups
            .flatMap(\.clips)
            .filter { $0.authorName == authorName }
            .max { $0.createdAt < $1.createdAt }
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
}
