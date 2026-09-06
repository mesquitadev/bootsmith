import Foundation

/// Uma imagem de disco a gravar, já inspecionada.
struct DiskImage: Identifiable, Sendable {
    /// Como a imagem vai bootar depois de gravada — o dado que o Rufus expõe
    /// como "esquema de partição" e que aqui é *detectado*, não escolhido:
    /// escolher errado é a causa mais comum de um pendrive que não boota.
    struct BootSupport: Sendable, Hashable {
        /// MBR com assinatura 0x55AA e código de boot — BIOS legado consegue iniciar.
        var legacyBIOS = false
        /// Existe uma EFI System Partition — máquinas UEFI conseguem iniciar.
        var uefi = false

        var label: String {
            switch (legacyBIOS, uefi) {
            case (true, true): "BIOS legado e UEFI"
            case (true, false): "só BIOS legado"
            case (false, true): "só UEFI"
            case (false, false): "nenhum modo de boot detectado"
            }
        }

        var isBootable: Bool { legacyBIOS || uefi }
    }

    let url: URL
    let format: ImageFormat
    /// Tamanho do arquivo em disco — menor que `size` quando comprimido.
    let fileSize: Int64
    /// Tamanho depois de expandido: é ele que precisa caber no dispositivo.
    let size: Int64
    /// Falso quando o formato não guarda o tamanho original (bzip2), caso em
    /// que `size` é só o tamanho do arquivo e a barra de progresso é estimada.
    let sizeIsExact: Bool
    let boot: BootSupport
    /// SHA-256 informado pelo usuário para conferência antes de gravar.
    var expectedChecksum: String?

    var id: URL { url }
    var name: String { url.lastPathComponent }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// "2,7 GB · comprimido de 1,1 GB"
    var sizeSummary: String {
        guard format.isCompressed else { return formattedSize }
        let packed = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        return sizeIsExact ? "\(formattedSize) · \(packed) compressed" : "\(packed) compressed"
    }
}
