import Foundation

/// Um dispositivo removível candidato a receber uma imagem.
///
/// Só entram aqui discos que o macOS reporta como externos, físicos e inteiros:
/// gravar numa partição em vez do disco inteiro produz um pendrive que não boota,
/// e gravar num disco interno destrói o sistema.
struct Drive: Identifiable, Sendable, Hashable {
    /// `disk6` — sem o `/dev/`.
    let id: String
    /// "Kingston DataTraveler 3.0 Media"
    let name: String
    /// USB, Thunderbolt, SATA…
    let busProtocol: String
    let size: Int64
    let isRemovable: Bool
    let isEjectable: Bool
    /// Volumes montados deste disco, para mostrar o que será perdido.
    let volumes: [String]

    /// `/dev/disk6` — o nó de bloco, usado para desmontar e ejetar.
    var deviceNode: String { "/dev/\(id)" }

    /// `/dev/rdisk6` — o nó "raw", sem buffer de cache. Gravar aqui é ordens de
    /// grandeza mais rápido do que no nó bufferizado.
    var rawDeviceNode: String { "/dev/r\(id)" }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Acima disto é quase certamente um HD ou SSD externo, não um pendrive.
    /// Não bloqueia — há pendrives de 256 GB — mas merece um aviso, porque
    /// gravar uma ISO num disco de backup apaga tudo.
    var looksLikeAnExternalDisk: Bool {
        size > 128 * 1_000_000_000
    }

    /// O que aparece na lista: "Kingston DataTraveler 3.0 · 31 GB · USB".
    var summary: String {
        "\(name) · \(formattedSize) · \(busProtocol)"
    }
}
