import SwiftUI

/// Shows `model.toast` as a capsule at the bottom of the results area.
struct ToastOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack {
            Spacer()
            if let toast = model.toast {
                ToastView(toast: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    // Sit above the "Move to Trash" bar.
                    .padding(.bottom, 72)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(duration: 0.35), value: model.toast?.id)
    }
}

private struct ToastView: View {
    @Environment(AppModel.self) private var model
    let toast: ToastInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isWarning ? Color.orange : Color.green)
                .font(.system(size: 18))
            Text(toast.message)
                .fixedSize(horizontal: false, vertical: true)
            if toast.details != nil {
                Button("Details") { model.showToastDetails() }
                    .buttonStyle(.link)
            }
            Button {
                model.dismissToast()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .font(.system(size: 14))
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .frame(maxWidth: 640)
    }
}
