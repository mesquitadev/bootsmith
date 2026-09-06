import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ImageSection(onPick: pickImage)
                    DriveSection()
                }
                .padding(20)
            }
            Divider()
            ActionBar(confirming: $confirming)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.load(url) }
            }
            return true
        }
        .sheet(isPresented: .constant(model.isBusy)) { ProgressSheet() }
        .sheet(isPresented: resultBinding) { ResultSheet() }
        .confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button(L.t("Erase and write"), role: .destructive) { model.write() }
            Button(L.t("Cancel"), role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private var confirmTitle: String {
        guard let image = model.image, let drive = model.selectedDrive else { return "" }
        return String(format: L.t("Erase %@ and write %@?"), drive.name, image.name)
    }

    /// Nomear os volumes que serão destruídos é o que transforma o aviso em
    /// informação: "PVE" diz muito mais do que "todos os dados".
    private var confirmMessage: String {
        guard let drive = model.selectedDrive else { return "" }
        guard !drive.volumes.isEmpty else { return L.t("This device has no mounted volumes.") }
        return String(format: L.t("Everything on this device will be lost: %@"),
                      drive.volumes.joined(separator: ", "))
    }

    private var resultBinding: Binding<Bool> {
        Binding(
            get: {
                if case .done = model.phase { return true }
                if case .failed = model.phase { return true }
                return false
            },
            set: { if !$0 { model.reset() } }
        )
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        // .img.xz e afins não têm tipo declarado no sistema, então o filtro é
        // por extensão além dos tipos conhecidos.
        panel.allowedContentTypes = [.diskImage, .archive, .data]
        panel.allowedFileTypes = ["iso", "img", "dmg", "xz", "gz", "zip", "bz2"]
        panel.prompt = L.t("Choose an image…")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.load(url)
    }
}

private struct ImageSection: View {
    @Environment(AppModel.self) private var model
    let onPick: () -> Void

    /// Numa imagem comprimida o que importa é o tamanho expandido — é ele que
    /// precisa caber no dispositivo —, mas o tamanho do arquivo explica a
    /// diferença que a pessoa vê no Finder.
    private func sizeSummary(_ image: DiskImage) -> String {
        guard image.format.isCompressed else { return image.formattedSize }
        let packed = ByteCountFormatter.string(fromByteCount: image.fileSize, countStyle: .file)
        return image.sizeIsExact
            ? "\(image.formattedSize) · \(String(format: L.t("%@ compressed"), packed))"
            : String(format: L.t("%@ compressed · final size unknown"), packed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("Image")).font(.headline)

            if let image = model.image {
                HStack(spacing: 12) {
                    Image(systemName: "opticaldisc")
                        .font(.title)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(image.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                        Text(sizeSummary(image)).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L.t("Choose an image…"), action: onPick)
                }
                BootBadge(boot: image.boot)
                ChecksumField()
            } else {
                Button(action: onPick) {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc").font(.largeTitle).foregroundStyle(.secondary)
                        Text(L.t("Drop an ISO here, or choose one")).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// O que o Rufus faz o usuário escolher — esquema de partição, sistema de destino —
/// aqui é lido da imagem e apenas informado. Escolher errado é a causa mais comum
/// de pendrive que não boota, e a imagem já sabe a resposta.
private struct BootBadge: View {
    let boot: DiskImage.BootSupport

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: boot.isBootable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(boot.isBootable ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(L.t("Boots on")): \(L.t(boot.label))")
                    .font(.callout.weight(.medium))
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var explanation: String {
        boot.legacyBIOS && boot.uefi
            ? L.t("Same stick works on old BIOS machines and new UEFI ones.")
            : boot.isBootable ? "" : L.t("This image has no boot signature — it will not start a computer.")
    }
}

private struct DriveSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.t("Destination")).font(.headline)
                Spacer()
                Button(L.t("Refresh"), systemImage: "arrow.clockwise") { model.refreshDrives() }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
            }

            if model.drives.isEmpty {
                VStack(spacing: 4) {
                    Text(L.t("No removable drives connected")).foregroundStyle(.secondary)
                    Text(L.t("Connect a USB drive to continue")).font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
            } else {
                ForEach(model.drives) { drive in
                    DriveRow(drive: drive, isSelected: model.selectedDriveID == drive.id)
                        .onTapGesture { model.selectedDriveID = drive.id }
                }
            }
        }
    }
}

private struct DriveRow: View {
    @Environment(AppModel.self) private var model
    let drive: Drive
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            Image(systemName: "externaldrive")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(drive.name).fontWeight(.medium).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let image = model.image, image.size > drive.size {
                Label(L.t("too small"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).labelStyle(.iconOnly).foregroundStyle(.orange)
                    .help(L.t("The image does not fit on this device."))
            } else if drive.looksLikeAnExternalDisk {
                // Um disco de 2 TB na lista quase sempre é backup, não pendrive.
                Label(L.t("large disk"), systemImage: "externaldrive.badge.questionmark")
                    .font(.caption).labelStyle(.iconOnly).foregroundStyle(.orange)
                    .help(L.t("This looks like an external disk rather than a USB stick."))
            }
        }
        .padding(10)
        .background(isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.quinary),
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(.rect)
    }

    private var subtitle: String {
        var parts = [drive.formattedSize, drive.busProtocol, drive.deviceNode]
        if !drive.volumes.isEmpty { parts.append(drive.volumes.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

private struct ActionBar: View {
    @Environment(AppModel.self) private var model
    @Binding var confirming: Bool

    var body: some View {
        HStack {
            Toggle(L.t("Verify after writing"), isOn: Binding(
                get: { model.verifyAfterWrite }, set: { model.verifyAfterWrite = $0 }))
                .toggleStyle(.checkbox)
            Spacer()
            EraseMenu()
            Button(L.t("Write")) { confirming = true }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canWrite)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

/// Conferência do SHA-256 antes de gravar. Aceita tanto o hash puro quanto o
/// conteúdo de um arquivo `SHA256SUMS` — que é como os projetos publicam, e é o
/// que a pessoa tem na mão ao baixar de releases.ubuntu.com.
private struct ChecksumField: View {
    @Environment(AppModel.self) private var model
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(L.t("Paste a SHA-256, or the contents of SHA256SUMS"),
                              text: Binding(get: { model.checksumInput },
                                            set: { model.checksumInput = $0 }),
                              axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .font(.caption.monospaced())

                    HStack {
                        Button(L.t("Check")) { model.verifyChecksum() }
                            .disabled(model.checksumInput.isEmpty || model.isBusy)
                        Spacer()
                        result
                    }
                }
                .padding(.top, 6)
            } label: {
                Label(L.t("Verify checksum"), systemImage: "number")
                    .font(.callout)
            }
        }
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var result: some View {
        switch model.checksumResult {
        case .checking(let fraction):
            HStack(spacing: 6) {
                ProgressView(value: fraction).progressViewStyle(.linear).frame(width: 90)
                Text("\(Int(fraction * 100))%").font(.caption.monospacedDigit())
            }
        case .matched:
            Label(L.t("Matches"), systemImage: "checkmark.seal.fill")
                .font(.caption).foregroundStyle(.green)
        case .mismatched:
            Label(L.t("Does not match — do not use this image"), systemImage: "xmark.octagon.fill")
                .font(.caption).foregroundStyle(.red)
        case .notFound:
            Label(L.t("No SHA-256 found for this file"), systemImage: "questionmark.circle")
                .font(.caption).foregroundStyle(.orange)
        case nil:
            EmptyView()
        }
    }
}

/// Reformatar o pendrive depois do uso. Fica atrás de um menu porque é uma ação
/// destrutiva que ninguém deve acionar por engano ao mirar em "Gravar".
struct EraseMenu: View {
    @Environment(AppModel.self) private var model
    @State private var confirming: DriveEraser.Filesystem?
    @State private var name = "UNTITLED"

    var body: some View {
        Menu {
            ForEach(DriveEraser.Filesystem.allCases) { filesystem in
                Button(String(format: L.t("Erase as %@"), filesystem.shortLabel)) {
                    confirming = filesystem
                }
            }
        } label: {
            Label(L.t("Restore drive"), systemImage: "eraser")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.selectedDrive == nil || model.isBusy)
        .confirmationDialog(
            confirming.map { String(format: L.t("Erase %@ as %@?"),
                                    model.selectedDrive?.name ?? "", $0.shortLabel) } ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            Button(L.t("Erase"), role: .destructive) {
                if let filesystem = confirming { model.erase(as: filesystem, named: name) }
                confirming = nil
            }
            Button(L.t("Cancel"), role: .cancel) { confirming = nil }
        } message: {
            Text(L.t("Everything on the drive will be lost, including the image you wrote."))
        }
    }
}
