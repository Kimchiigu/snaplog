//
//  PlaybackModels.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 09/09/26.
//

import Foundation

/// A playable clip from `GET /api/rooms/:id/playback`.
struct PlaybackClip: Identifiable, Codable, Hashable, Sendable {
    let s3Key: String
    let url: String
    let duration: Double
    let createdAt: Date
    let authorName: String

    var id: String { s3Key }
    var playbackURL: URL { URL(string: url) ?? URL(fileURLWithPath: "/dev/null") }
}

/// Clips bucketed by the hour they were captured, e.g. "15.00".
struct HourlyClipGroup: Identifiable, Hashable, Sendable {
    let hourLabel: String
    let clips: [PlaybackClip]

    var id: String { hourLabel }
}

enum ClipGrouper {
    /// Groups clips into hourly buckets, newest hour first, clips newest first.
    static func groupByHour(_ clips: [PlaybackClip], calendar: Calendar = .current) -> [HourlyClipGroup] {
        let grouped = Dictionary(grouping: clips) { clip -> DateComponents in
            calendar.dateComponents([.year, .month, .day, .hour], from: clip.createdAt)
        }
        return grouped
            .map { components, groupClips in
                HourlyClipGroup(
                    hourLabel: String(format: "%02d.00", components.hour ?? 0),
                    clips: groupClips.sorted { $0.createdAt > $1.createdAt }
                )
            }
            .sorted { lhs, rhs in
                let lFirst = lhs.clips.first?.createdAt ?? .distantPast
                let rFirst = rhs.clips.first?.createdAt ?? .distantPast
                return lFirst > rFirst
            }
    }
}
