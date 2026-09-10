//
//  Theme.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 09/09/26.
//

import SwiftUI

/// SnapLog's dark, minimalist, playful visual language: OLED-black canvas,
/// charcoal containers, cyan accents, and pink/blue smileys.
enum Theme {

    // MARK: Colors

    /// True OLED black canvas.
    static let canvas = Color(hex: 0x000000)
    /// Primary dark charcoal card container.
    static let card = Color(hex: 0x18181A)
    /// Elevated / secondary charcoal container.
    static let cardElevated = Color(hex: 0x222224)
    /// Muted gray for subtitles and metadata.
    static let muted = Color(hex: 0x8E8E93)
    /// Bright cyan for primary actions, status, and checkmarks.
    static let accent = Color(hex: 0x00D2FF)
    /// Playful hot pink for smiley stickers.
    static let pink = Color(hex: 0xFF2D55)
    /// Royal blue for smiley stickers.
    static let blue = Color(hex: 0x2B62F6)

    /// The stylized blue→purple brand gradient for "SNAPLOG".
    static let brandGradient = LinearGradient(
        colors: [Color(hex: 0x2B62F6), Color(hex: 0x8B5CF6), Color(hex: 0xB249F8)],
        startPoint: .leading,
        endPoint: .trailing
    )

    // MARK: Typography

    /// Stylized wordmark used in the home header.
    static func brandText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .black, design: .rounded))
            .kerning(1.5)
            .foregroundStyle(brandGradient)
    }

    /// Bold monospaced timestamp overlay, e.g. "20:00".
    static func timestamp(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 30, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.6), radius: 4)
    }
}

/// A colored smiley sticker — SnapLog's playful avatar/badge mark.
struct SmileyIcon: View {
    enum Mood {
        case plain
        case upsideDown

        var rotates: Bool { self == .upsideDown }
    }

    var color: Color = Theme.accent
    var mood: Mood = .plain
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: "face.smiling")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .rotationEffect(.degrees(mood.rotates ? 180 : 0))
            .accessibilityLabel("Smiley face")
    }
}

/// The current wall-clock time as "20:00", ticking every second.
struct LiveTimestamp: View {
    var style: Font = .system(size: 30, weight: .bold, design: .monospaced)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.formatted(context.date))
                .font(style)
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.6), radius: 4)
        }
    }

    nonisolated static func formatted(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}

extension Color {
    /// Initializes a color from a 24-bit RGB hex value.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Room {
    /// Short relative label for the room's most recent activity, e.g. "sent log 2min".
    var lastActivityLabel: String? {
        guard let latest = timeline.map(\.createdAt).max() else { return nil }
        let date = Date(timeIntervalSince1970: latest)
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "sent log now" }
        if minutes < 60 { return "sent log \(minutes)min" }
        let hours = minutes / 60
        return hours < 24 ? "sent log \(hours)h" : "sent log \(hours / 24)d"
    }

    /// Whether any clip arrived recently enough to badge the room as unread.
    var hasFreshActivity: Bool {
        guard let latest = timeline.map(\.createdAt).max() else { return false }
        return Date().timeIntervalSince(Date(timeIntervalSince1970: latest)) < 3600
    }
}
