import Foundation

/// Descobre como uma imagem vai bootar, lendo a própria imagem.
///
/// Uma ISO híbrida moderna (Ubuntu, Debian, Proxmox, Fedora) carrega as duas
/// coisas ao mesmo tempo: um MBR com código de boot para BIOS e uma EFI System
/// Partition para UEFI. Por isso a gravação é uma cópia byte a byte — qualquer
/// "conversão" de esquema quebraria um dos dois caminhos.
struct ImageInspector: Sendable {
    enum InspectionError: LocalizedError {
        case unreadable(URL)
        case tooSmall

        var errorDescription: String? {
            switch self {
            case .unreadable(let url): "Não foi possível ler \(url.lastPathComponent)."
            case .tooSmall: "O arquivo é pequeno demais para ser uma imagem de disco."
            }
        }
    }

    func inspect(_ url: URL) throws -> DiskImage {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw InspectionError.unreadable(url)
        }
        defer { try? handle.close() }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard size > 2048 else { throw InspectionError.tooSmall }

        guard let mbr = try handle.read(upToCount: 512), mbr.count == 512 else {
            throw InspectionError.unreadable(url)
        }

        var boot = DiskImage.BootSupport()
        // Assinatura de boot no fim do primeiro setor. Sem ela, nenhuma BIOS
        // sequer tenta iniciar o disco.
        boot.legacyBIOS = mbr[510] == 0x55 && mbr[511] == 0xAA
        boot.uefi = try hasEFISystemPartition(handle: handle, mbr: mbr)

        return DiskImage(url: url, size: size, boot: boot, sha256: nil)
    }

    /// Procura uma EFI System Partition, nos dois esquemas em que ela pode estar.
    private func hasEFISystemPartition(handle: FileHandle, mbr: Data) throws -> Bool {
        // No MBR, tipo 0xEF é uma ESP direta; 0xEE é o "protective MBR" que diz
        // que o esquema real é GPT e que devemos ler o cabeçalho no setor 1.
        var isGPT = false
        for slot in 0..<4 {
            let type = mbr[446 + slot * 16 + 4]
            if type == 0xEF { return true }
            if type == 0xEE { isGPT = true }
        }
        guard isGPT else { return false }

        try handle.seek(toOffset: 512)
        guard let header = try handle.read(upToCount: 512), header.count == 512,
              header.prefix(8).elementsEqual("EFI PART".utf8)
        else { return false }

        let entryLBA = header.readLittleEndian(UInt64.self, at: 72)
        let entryCount = header.readLittleEndian(UInt32.self, at: 80)
        let entrySize = header.readLittleEndian(UInt32.self, at: 84)
        guard entryCount > 0, entryCount < 1024, entrySize >= 128 else { return false }

        try handle.seek(toOffset: entryLBA * 512)
        guard let table = try handle.read(upToCount: Int(entryCount * entrySize)) else { return false }

        // GUID do tipo "EFI System Partition", em little-endian de campo misto.
        let espGUID: [UInt8] = [0x28, 0x73, 0x2A, 0xC1, 0x1F, 0xF8, 0xD2, 0x11,
                                0xBA, 0x4B, 0x00, 0xA0, 0xC9, 0x3E, 0xC9, 0x3B]
        for index in 0..<Int(entryCount) {
            let start = index * Int(entrySize)
            guard start + 16 <= table.count else { break }
            if Array(table[start..<(start + 16)]) == espGUID { return true }
        }
        return false
    }
}

private extension Data {
    /// Lê um inteiro little-endian de um deslocamento, sem assumir alinhamento.
    func readLittleEndian<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        var value: T = 0
        let width = MemoryLayout<T>.size
        guard offset + width <= count else { return 0 }
        for byte in (0..<width).reversed() {
            value = (value << 8) | T(self[startIndex + offset + byte])
        }
        return value
    }
}
