import SwiftUI

/// Shown in the proofreading dialog while the model works
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)
                .progressViewStyle(.circular)
            Text("Proofreading…")
                .font(Focus.header)
                .foregroundColor(Focus.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
