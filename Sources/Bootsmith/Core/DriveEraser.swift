import Foundation

/// Devolve um pendrive ao uso comum.
///
/// Depois de receber uma ISO, o pendrive fica com partições que o Finder não
/// monta: para o macOS ele vira um disco "ilegível" que só oferece Inicializar.
/// Reformatar resolve, e é o passo que todo mundo procura depois de instalar o
/// sistema — o Rufus não faz isso, e no Utilitário de Disco dá voltas.
enum DriveEraser {
    enum Filesystem: String, CaseIterable, Identifiable, Sendable {
        case exFAT = "ExFAT"
        case fat32 = "MS-DOS FAT32"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .exFAT: "exFAT — arquivos de qualquer tamanho, lido por macOS, Windows e Linux"
            case .fat32: "FAT32 — máxima compatibilidade, arquivos até 4 GB"
            }
        }

        var shortLabel: String {
            switch self {
            case .exFAT: "exFAT"
            case .fat32: "FAT32"
            }
        }
    }

    /// `diskutil eraseDisk` pede a própria autorização quando necessário e
    /// recria a tabela de partição — por isso reformatar não precisa do
    /// caminho privilegiado da gravação.
    static func erase(_ drive: Drive, as filesystem: Filesystem, named name: String) throws {
        let volumeName = name.isEmpty ? "UNTITLED" : String(name.prefix(11)).uppercased()
        _ = try Shell.run("/usr/sbin/diskutil", [
            "eraseDisk", filesystem.rawValue, volumeName, "MBRFormat", drive.deviceNode,
        ])
    }
}
