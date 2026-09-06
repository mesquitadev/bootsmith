import Foundation

/// Enumera os dispositivos removíveis via `diskutil`.
///
/// Usamos a saída em plist do `diskutil` em vez de DiskArbitration porque é o
/// mesmo dado, é estável entre versões do macOS, e mantém a ferramenta legível
/// para quem quiser conferir o que ela faz antes de deixá-la escrever num disco.
struct DriveScanner: Sendable {
    enum ScanError: LocalizedError {
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .commandFailed(let message): "diskutil falhou: \(message)"
            }
        }
    }

    func scan() throws -> [Drive] {
        let listing = try Shell.run("/usr/sbin/diskutil", ["list", "-plist", "external", "physical"])
        guard let plist = try PropertyListSerialization.propertyList(
            from: Data(listing.utf8), options: [], format: nil) as? [String: Any],
            let wholeDisks = plist["WholeDisks"] as? [String]
        else { return [] }

        return try wholeDisks.compactMap { try describe($0) }
            .sorted { $0.id < $1.id }
    }

    private func describe(_ identifier: String) throws -> Drive? {
        let output = try Shell.run("/usr/sbin/diskutil", ["info", "-plist", identifier])
        guard let info = try PropertyListSerialization.propertyList(
            from: Data(output.utf8), options: [], format: nil) as? [String: Any]
        else { return nil }

        // Três garantias antes de um disco sequer aparecer na lista. Nenhuma delas
        // é redundante: um disco interno destruiria o sistema, um disco virtual
        // (imagem montada) não é um alvo real, e uma partição solta não boota.
        guard info["Internal"] as? Bool == false,
              info["VirtualOrPhysical"] as? String == "Physical",
              info["WholeDisk"] as? Bool == true
        else { return nil }

        let size = (info["Size"] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { return nil }

        return Drive(
            id: identifier,
            name: (info["IORegistryEntryName"] as? String)
                ?? (info["MediaName"] as? String)
                ?? identifier,
            busProtocol: info["BusProtocol"] as? String ?? "desconhecido",
            size: size,
            isRemovable: info["RemovableMedia"] as? Bool ?? false,
            isEjectable: info["Ejectable"] as? Bool ?? false,
            volumes: try mountedVolumes(of: identifier)
        )
    }

    /// Nomes dos volumes montados do disco — é isso que o usuário reconhece como
    /// "o que vou perder".
    private func mountedVolumes(of identifier: String) throws -> [String] {
        let output = try Shell.run("/usr/sbin/diskutil", ["list", "-plist", identifier])
        guard let plist = try PropertyListSerialization.propertyList(
            from: Data(output.utf8), options: [], format: nil) as? [String: Any],
            let disks = plist["AllDisksAndPartitions"] as? [[String: Any]]
        else { return [] }

        return disks.flatMap { disk -> [String] in
            let partitions = disk["Partitions"] as? [[String: Any]] ?? []
            return partitions.compactMap { $0["VolumeName"] as? String }
        }
    }
}
