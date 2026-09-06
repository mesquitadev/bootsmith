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
    let size: Int64
    let boot: BootSupport
    /// SHA-256, calculado sob demanda: em imagem de 3 GB isso leva segundos.
    var sha256: String?

    var id: URL { url }
    var name: String { url.lastPathComponent }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
