import Foundation

/// Descobre como uma imagem vai bootar e quanto ela ocupa depois de expandida.
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
            case .unreadable(let url): "Could not read \(url.lastPathComponent)."
            case .tooSmall: "The file is too small to be a disk image."
            }
        }
    }

    func inspect(_ url: URL) throws -> DiskImage {
        let format = ImageFormat.detect(url)
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard fileSize > 2048 else { throw InspectionError.tooSmall }

        // O cabeçalho é lido através da descompressão: numa imagem comprimida o
        // MBR só existe depois de expandir.
        let stream = try ImageSource.open(url, format: format)
        defer { stream.close() }

        var header = Data()
        while header.count < 34 * 512 {
            let piece = try stream.read(upTo: 34 * 512 - header.count)
            if piece.isEmpty { break }
            header.append(piece)
        }
        guard header.count >= 512 else { throw InspectionError.unreadable(url) }

        var boot = DiskImage.BootSupport()
        boot.legacyBIOS = header[510] == 0x55 && header[511] == 0xAA
        boot.uefi = hasEFISystemPartition(in: header)

        let expanded = try expandedSize(of: url, format: format)
        return DiskImage(
            url: url,
            format: format,
            fileSize: fileSize,
            size: expanded ?? fileSize,
            sizeIsExact: expanded != nil,
            boot: boot
        )
    }

    /// Tamanho depois de expandir. Sabê-lo antes evita começar uma gravação que
    /// não cabe — e é o que permite mostrar uma barra de progresso honesta.
    private func expandedSize(of url: URL, format: ImageFormat) throws -> Int64? {
        switch format {
        case .raw:
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        case .gzip:
            return gzipExpandedSize(url)
        case .xz:
            return xzExpandedSize(url)
        case .zip:
            return zipExpandedSize(url)
        case .bzip2:
            // O formato não guarda o tamanho original em lugar algum.
            return nil
        }
    }

    /// O gzip guarda o tamanho original nos últimos 4 bytes, módulo 2^32 — o que
    /// só é confiável abaixo de 4 GB. Acima disso preferimos não afirmar nada.
    private func gzipExpandedSize(_ url: URL) -> Int64? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(), end > 4 else { return nil }
        try? handle.seek(toOffset: end - 4)
        guard let tail = try? handle.read(upToCount: 4), tail.count == 4 else { return nil }
        let size = tail.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
        return size > 0 ? Int64(size) : nil
    }

    /// O xz termina com um rodapé de 12 bytes que aponta para o índice, e o
    /// índice lista o tamanho descomprimido de cada bloco.
    private func xzExpandedSize(_ url: URL) -> Int64? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(), end > 12 else { return nil }

        try? handle.seek(toOffset: end - 12)
        guard let footer = try? handle.read(upToCount: 12), footer.count == 12,
              footer.suffix(2).elementsEqual([0x59, 0x5A])   // "YZ"
        else { return nil }

        let backwardSize = (Int64(footer.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian
        }) + 1) * 4
        guard backwardSize > 0, end >= UInt64(backwardSize) + 12 else { return nil }

        try? handle.seek(toOffset: end - 12 - UInt64(backwardSize))
        guard let index = try? handle.read(upToCount: Int(backwardSize)), index.count >= 2,
              index[0] == 0x00   // indicador de índice
        else { return nil }

        var cursor = 1
        guard let records = readVarint(index, at: &cursor), records > 0, records < 1_000_000
        else { return nil }

        var total: Int64 = 0
        for _ in 0..<records {
            guard readVarint(index, at: &cursor) != nil,                 // unpadded size
                  let uncompressed = readVarint(index, at: &cursor)
            else { return nil }
            total += Int64(uncompressed)
        }
        return total > 0 ? total : nil
    }

    /// Inteiro de tamanho variável do xz: sete bits por byte, o oitavo indicando
    /// continuação.
    private func readVarint(_ data: Data, at cursor: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while cursor < data.count, shift < 63 {
            let byte = data[data.startIndex + cursor]
            cursor += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }

    private func zipExpandedSize(_ url: URL) -> Int64? {
        guard let output = try? Shell.run("/usr/bin/unzip", ["-l", url.path]) else { return nil }
        // A última linha com números traz o total descomprimido.
        for line in output.split(separator: "\n").reversed() {
            let fields = line.split(separator: " ").map(String.init)
            if let first = fields.first, let size = Int64(first), size > 0 { return size }
        }
        return nil
    }

    /// Procura uma EFI System Partition, nos dois esquemas em que ela pode estar.
    private func hasEFISystemPartition(in header: Data) -> Bool {
        var isGPT = false
        for slot in 0..<4 {
            let type = header[446 + slot * 16 + 4]
            if type == 0xEF { return true }
            if type == 0xEE { isGPT = true }
        }
        guard isGPT, header.count >= 1024 else { return false }

        let gptHeader = header[512..<1024]
        guard gptHeader.prefix(8).elementsEqual("EFI PART".utf8) else { return false }

        let entryLBA = gptHeader.readLittleEndian(UInt64.self, at: 72)
        let entryCount = gptHeader.readLittleEndian(UInt32.self, at: 80)
        let entrySize = gptHeader.readLittleEndian(UInt32.self, at: 84)
        guard entryCount > 0, entryCount < 1024, entrySize >= 128 else { return false }

        let tableStart = Int(entryLBA * 512)
        let espGUID: [UInt8] = [0x28, 0x73, 0x2A, 0xC1, 0x1F, 0xF8, 0xD2, 0x11,
                                0xBA, 0x4B, 0x00, 0xA0, 0xC9, 0x3E, 0xC9, 0x3B]

        for index in 0..<Int(entryCount) {
            let start = tableStart + index * Int(entrySize)
            guard start + 16 <= header.count else { break }
            if Array(header[start..<(start + 16)]) == espGUID { return true }
        }
        return false
    }
}

private extension Data {
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
