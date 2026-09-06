import SwiftUI

struct ResultSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(tint)

            Text(headline)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            if let note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(L.t("Done")) { model.reset() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 380)
    }

    private var isFailure: Bool {
        if case .failed = model.phase { return true }
        if case .done(_, let verified, _) = model.phase { return !verified }
        return false
    }

    private var symbol: String { isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill" }
    private var tint: Color { isFailure ? .orange : .green }

    private var headline: String {
        switch model.phase {
        case .done(let bytes, let verified, _):
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            return String(format: L.t(verified ? "%@ written and verified" : "%@ written"), size)
        case .erased(let filesystem):
            return String(format: L.t("Drive restored as %@"), filesystem)
        case .failed(let message):
            return message
        default:
            return ""
        }
    }

    private var note: String? {
        switch model.phase {
        case .done(_, let verified, let ejected):
            if !verified { return L.t("Verification failed: the drive does not match the image.") }
            return ejected ? L.t("The drive was ejected — you can unplug it.") : nil
        case .erased:
            return L.t("You can use it in Finder again.")
        default:
            return nil
        }
    }
}
