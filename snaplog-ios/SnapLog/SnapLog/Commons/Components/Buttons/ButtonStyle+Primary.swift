//
//  ButtonStyle+Primary.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import SwiftUI

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primaryProminent: PrimaryButtonStyle { PrimaryButtonStyle() }
}

struct PrimaryButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(.tint, in: .rect(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}
