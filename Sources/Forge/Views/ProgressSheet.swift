import SwiftUI

/// Folha modal durante a gravação. Além de mostrar o andamento, ela é a trava:
/// enquanto está na tela não dá para trocar de imagem, de dispositivo, nem
/// disparar outra gravação.
struct ProgressSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
            }

            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .animation(.default, value: fraction)

            Text(L.t("Do not unplug the drive."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
        .interactiveDismissDisabled()
    }

    private var symbol: String {
        switch model.phase {
        case .verifying: "checkmark.shield"
        default: "arrow.down.circle"
        }
    }

    private var title: String {
        switch model.phase {
        case .unmounting: L.t("Unmounting the device…")
        case .verifying: L.t("Verifying")
        default: L.t("Writing")
        }
    }

    private var fraction: Double {
        switch model.phase {
        case .writing(let progress): progress.fraction
        case .verifying(let value): value
        default: 0
        }
    }

    private var detail: String {
        guard case .writing(let progress) = model.phase else {
            if case .verifying(let value) = model.phase {
                return "\(Int(value * 100))%"
            }
            return ""
        }
        let written = ByteCountFormatter.string(fromByteCount: progress.bytesWritten, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file)
        var text = String(format: L.t("%@ of %@"), written, total)

        if progress.bytesPerSecond > 0 {
            let rate = ByteCountFormatter.string(fromByteCount: Int64(progress.bytesPerSecond), countStyle: .file)
            text += " · " + String(format: L.t("%@/s"), rate)
        }
        if let remaining = progress.remaining {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.minute, .second]
            formatter.unitsStyle = .abbreviated
            if let pretty = formatter.string(from: remaining) {
                text += " · " + String(format: L.t("about %@ left"), pretty)
            }
        }
        return text
    }
}
