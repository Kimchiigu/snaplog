//
//  DoodleBackground.swift
//  SnapLog
//

import SwiftUI

struct DoodleBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                // Background Base Color
                Color(hex: 0xF9F8F3)
                    .ignoresSafeArea()

                // TOP CLUSTER: Stars, Cloud Mascot, Moon, Letter
                LetterDoodle()
                    .position(x: size.width * 0.12, y: size.height * 0.28)

                StarDoodle(hasFace: true)
                    .position(x: size.width * 0.28, y: size.height * 0.11)

                CloudMascot()
                    .position(x: size.width * 0.52, y: size.height * 0.22)

                SparkleDoodle()
                    .position(x: size.width * 0.52, y: size.height * 0.11)

                StarDoodle(hasFace: true)
                    .position(x: size.width * 0.76, y: size.height * 0.12)

                CrescentMoonDoodle()
                    .position(x: size.width * 0.88, y: size.height * 0.28)

                // MID CLUSTER: Pizza, Peach, Plant
                PizzaDoodle()
                    .position(x: size.width * 0.18, y: size.height * 0.51)

                PeachDoodle()
                    .position(x: size.width * 0.44, y: size.height * 0.54)

                PlantVaseDoodle()
                    .position(x: size.width * 0.82, y: size.height * 0.51)

                // BOTTOM CLUSTER: Tea Mug, Flames, Ice Cream
                TeaMugDoodle()
                    .position(x: size.width * 0.2, y: size.height * 0.88)

                FlameClusterDoodle()
                    .position(x: size.width * 0.51, y: size.height * 0.91)

                IceCreamDoodle()
                    .position(x: size.width * 0.82, y: size.height * 0.87)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Individual Vector Doodles

/// Main Central Cloud Mascot
struct CloudMascot: View {
    var body: some View {
        ZStack {
            // Cloud Base
            CloudShape()
                .fill(Color(hex: 0xFCEBA6))
            CloudShape()
                .stroke(Color.black, lineWidth: 2.5)

            // Left Eye
            Group {
                Circle().fill(.white).frame(width: 22, height: 26)
                Circle().stroke(.black, lineWidth: 2).frame(width: 22, height: 26)
                Circle().fill(.black).frame(width: 10, height: 12).offset(x: -2, y: 1)
            }
            .offset(x: -12, y: -8)

            // Right Eye
            Group {
                Circle().fill(.white).frame(width: 22, height: 26)
                Circle().stroke(.black, lineWidth: 2).frame(width: 22, height: 26)
                Circle().fill(.black).frame(width: 10, height: 12).offset(x: -2, y: 1)
            }
            .offset(x: 12, y: -8)

            // Smile
            DoodleArc()
                .stroke(Color.black, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 12, height: 8)
                .offset(x: 10, y: 14)
        }
        .frame(width: 140, height: 100)
    }
}

/// Star with Face and Sparkle Rays
struct StarDoodle: View {
    var hasFace: Bool = false

    var body: some View {
        ZStack {
            StarShape()
                .fill(Color(hex: 0xFCEBA6))
            StarShape()
                .stroke(Color.black, lineWidth: 2)

            if hasFace {
                // Eyes (^ ^) or (- -)
                DoodleArc()
                    .stroke(Color.black, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 5, height: 3)
                    .offset(x: -6, y: -2)

                DoodleArc()
                    .stroke(Color.black, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 5, height: 3)
                    .offset(x: 6, y: -2)

                // Small mouth
                Circle()
                    .fill(Color.black)
                    .frame(width: 3, height: 3)
                    .offset(x: 0, y: 4)
            }
        }
        .frame(width: 48, height: 48)
    }
}

/// Crescent Moon with Sleeping Face
struct CrescentMoonDoodle: View {
    var body: some View {
        ZStack {
            MoonShape()
                .fill(Color(hex: 0xFCEBA6))
            MoonShape()
                .stroke(Color.black, lineWidth: 2)

            // Sleeping Eye (^)
            DoodleArc()
                .stroke(Color.black, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 6, height: 3)
                .offset(x: 8, y: -4)
        }
        .frame(width: 40, height: 50)
    }
}

/// Pizza Slice Doodle
struct PizzaDoodle: View {
    var body: some View {
        ZStack {
            PizzaShape()
                .fill(Color(hex: 0xFCEBA6))
            PizzaShape()
                .stroke(Color.black, lineWidth: 2)

            // Pepperoni dots
            Circle().fill(Color(hex: 0xE85A4F)).frame(width: 8, height: 8).offset(x: -10, y: -2)
            Circle().fill(Color(hex: 0xE85A4F)).frame(width: 8, height: 8).offset(x: 10, y: 2)
            Circle().fill(Color(hex: 0xE85A4F)).frame(width: 8, height: 8).offset(x: -2, y: 12)
        }
        .frame(width: 70, height: 60)
        .rotationEffect(.degrees(-15))
    }
}

/// Plant in Purple Vase
struct PlantVaseDoodle: View {
    var body: some View {
        ZStack {
            // Vines
            Path { path in
                path.move(to: CGPoint(x: 30, y: 40))
                path.addQuadCurve(to: CGPoint(x: 10, y: 10), control: CGPoint(x: 15, y: 25))
                path.move(to: CGPoint(x: 35, y: 40))
                path.addQuadCurve(to: CGPoint(x: 55, y: 5), control: CGPoint(x: 40, y: 15))
            }
            .stroke(Color(hex: 0x55B97D), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            // Vase
            VaseShape()
                .fill(Color(hex: 0x9D81E8))
            VaseShape()
                .stroke(Color.black, lineWidth: 2)
        }
        .frame(width: 60, height: 75)
    }
}

/// Tea Mug with Purple Steam
struct TeaMugDoodle: View {
    var body: some View {
        ZStack {
            // Mug
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white)
                .frame(width: 36, height: 38)
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.black, lineWidth: 2)
                .frame(width: 36, height: 38)

            Text("Tea")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x55B97D))
                .offset(y: 4)

            // Steam
            Path { path in
                path.move(to: CGPoint(x: 18, y: 0))
                path.addQuadCurve(to: CGPoint(x: 18, y: -18), control: CGPoint(x: 24, y: -9))
            }
            .stroke(Color(hex: 0x9D81E8), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .frame(width: 50, height: 50)
    }
}

/// Ice Cream Sundae
struct IceCreamDoodle: View {
    var body: some View {
        ZStack {
            // Scoop
            Circle()
                .fill(Color(hex: 0xFCEBA6))
                .frame(width: 36, height: 36)
                .offset(y: -10)
            Circle()
                .stroke(Color.black, lineWidth: 2)
                .frame(width: 36, height: 36)
                .offset(y: -10)

            // Glass Cup
            IceCreamCupShape()
                .fill(Color(hex: 0xC5E5FC))
            IceCreamCupShape()
                .stroke(Color.black, lineWidth: 2)

            // Cherry
            Circle()
                .fill(Color(hex: 0xE85A4F))
                .frame(width: 8, height: 8)
                .offset(y: -30)
        }
        .frame(width: 45, height: 60)
    }
}

struct PeachDoodle: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: 0xFFA053)).frame(width: 24, height: 24)
            Circle().stroke(Color.black, lineWidth: 2).frame(width: 24, height: 24)
        }
    }
}

struct SparkleDoodle: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 16))
            .foregroundStyle(Color.black)
    }
}

struct LetterDoodle: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color.white).frame(width: 28, height: 20)
            RoundedRectangle(cornerRadius: 4).stroke(Color.black, lineWidth: 1.5).frame(width: 28, height: 20)
            Image(systemName: "heart.fill").font(.system(size: 8)).foregroundStyle(Color(hex: 0xE85A4F))
        }
    }
}

struct FlameClusterDoodle: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill").font(.system(size: 12)).foregroundStyle(Color(hex: 0xFF6B4A))
            Image(systemName: "flame.fill").font(.system(size: 16)).foregroundStyle(Color(hex: 0xFF6B4A))
        }
    }
}

// MARK: - Custom Vector Shapes

struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.2, y: rect.height * 0.8))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.1, y: rect.height * 0.4), control: CGPoint(x: 0, y: rect.height * 0.6))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.4, y: rect.height * 0.1), control: CGPoint(x: rect.width * 0.15, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.8, y: rect.height * 0.2), control: CGPoint(x: rect.width * 0.6, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.9, y: rect.height * 0.7), control: CGPoint(x: rect.width, y: rect.height * 0.4))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.2, y: rect.height * 0.8), control: CGPoint(x: rect.width * 0.6, y: rect.height))
        return path
    }
}

struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.width / 2, y: rect.height / 2)
        let points = 5
        let outerRadius = rect.width / 2
        let innerRadius = outerRadius * 0.45
        let angle = .pi / Double(points)

        for pointIndex in 0..<points * 2 {
            let radius = pointIndex.isMultiple(of: 2) ? outerRadius : innerRadius
            let xPosition = center.x + CGFloat(cos(Double(pointIndex) * angle - .pi / 2)) * radius
            let yPosition = center.y + CGFloat(sin(Double(pointIndex) * angle - .pi / 2)) * radius
            let point = CGPoint(x: xPosition, y: yPosition)

            if pointIndex == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

struct MoonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.6, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.6, y: rect.height), control: CGPoint(x: 0, y: rect.height * 0.5))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.6, y: 0), control: CGPoint(x: rect.width * 0.3, y: rect.height * 0.5))
        return path
    }
}

struct PizzaShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width / 2, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: 10))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: 10), control: CGPoint(x: rect.width / 2, y: 0))
        path.closeSubpath()
        return path
    }
}

struct VaseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.3, y: rect.height * 0.4))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.7, y: rect.height * 0.4), control: CGPoint(x: rect.width / 2, y: rect.height * 0.35))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.8, y: rect.height * 0.7), control: CGPoint(x: rect.width, y: rect.height * 0.55))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.2, y: rect.height * 0.7), control: CGPoint(x: rect.width / 2, y: rect.height * 0.85))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.3, y: rect.height * 0.4), control: CGPoint(x: 0, y: rect.height * 0.55))
        return path
    }
}

struct IceCreamCupShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 5, y: rect.height * 0.4))
        path.addLine(to: CGPoint(x: rect.width - 5, y: rect.height * 0.4))
        path.addLine(to: CGPoint(x: rect.width * 0.65, y: rect.height * 0.85))
        path.addLine(to: CGPoint(x: rect.width * 0.65, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width * 0.35, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width * 0.35, y: rect.height * 0.85))
        path.closeSubpath()
        return path
    }
}

struct DoodleArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

// MARK: - Color Extension Helper
extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
