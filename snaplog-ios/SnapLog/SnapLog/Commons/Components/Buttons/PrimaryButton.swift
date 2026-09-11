import SwiftUI

struct PrimaryButton: View {
    let title: String
    let systemImage: String?
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.primaryProminent)
        .disabled(isLoading)
        .accessibilityLabel(title)
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton(title: "Continue", systemImage: "arrow.right") {}
        PrimaryButton(title: "Loading…", systemImage: nil, isLoading: true) {}
    }
    .padding()
}
