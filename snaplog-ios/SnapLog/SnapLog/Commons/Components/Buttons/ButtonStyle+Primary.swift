import SwiftUI

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primaryProminent: PrimaryButtonStyle { PrimaryButtonStyle() }
}

struct PrimaryButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .glassEffect(.regular.tint(.black.opacity(0.55)), in: .capsule)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}
