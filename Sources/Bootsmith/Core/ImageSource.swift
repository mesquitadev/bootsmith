import Foundation
import Compression

/// Uma fonte de bytes já descomprimidos.
///
/// Raspberry Pi OS, Armbian, OpenWrt e boa parte das imagens de placa são
/// distribuídas comprimidas. Descompactar à mão antes de gravar custa o dobro
/// de espaço em disco e um passo a mais; aqui a descompressão acontece em
/// fluxo, bloco a bloco, e nada intermediário toca o disco.
protocol ByteStream: AnyObject {
    /// Devolve até `count` bytes. Vazio significa fim do fluxo.
    func read(upTo count: Int) throws -> Data
    func close()
}

enum ImageFormat: Sendable {
    case raw
    case xz
    case gzip
    case zip
    case bzip2

    /// O formato vem da extensão porque é o que o usuário vê; a leitura real
    /// falha cedo e com mensagem clara se a extensão mentir.
    static func detect(_ url: URL) -> ImageFormat {
        switch url.pathExtension.lowercased() {
        case "xz": .xz
        case "gz", "tgz": .gzip
        case "zip": .zip
        case "bz2": .bzip2
        default: .raw
        }
    }

    var isCompressed: Bool { self != .raw }
}

enum ImageSource {
    enum SourceError: LocalizedError {
        case cannotOpen(URL)
        case decompressionFailed(String)

        var errorDescription: String? {
            switch self {
            case .cannotOpen(let url): "Could not read \(url.lastPathComponent)."
            case .decompressionFailed(let detail): "Decompression failed: \(detail)"
            }
        }
    }

    static func open(_ url: URL, format: ImageFormat) throws -> ByteStream {
        switch format {
        case .raw:
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                throw SourceError.cannotOpen(url)
            }
            return FileStream(handle: handle)
        case .xz:
            // O framework Compression da Apple lê o container xz sob o algoritmo
            // LZMA, então não precisamos da ferramenta `xz`, que não vem no macOS.
            return try LZMAStream(url: url)
        case .gzip:
            return try ProcessStream(executable: "/usr/bin/gunzip", arguments: ["-c", url.path])
        case .zip:
            // -p escreve o primeiro arquivo do zip em stdout, sem extrair para disco.
            return try ProcessStream(executable: "/usr/bin/unzip", arguments: ["-p", url.path])
        case .bzip2:
            return try ProcessStream(executable: "/usr/bin/bzip2", arguments: ["-dc", url.path])
        }
    }
}

/// Leitura direta, para imagens não comprimidas.
private final class FileStream: ByteStream {
    private let handle: FileHandle
    init(handle: FileHandle) { self.handle = handle }

    func read(upTo count: Int) throws -> Data {
        (try handle.read(upToCount: count)) ?? Data()
    }

    func close() { try? handle.close() }
}

/// Descompressão delegada a um utilitário do sistema, lida pelo stdout.
private final class ProcessStream: ByteStream {
    private let process = Process()
    private let output = Pipe()

    init(executable: String, arguments: [String]) throws {
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
    }

    func read(upTo count: Int) throws -> Data {
        // `read` de um pipe devolve o que estiver disponível, que pode ser menos
        // que o pedido sem significar fim de fluxo; o laço completa o bloco.
        var buffer = Data()
        while buffer.count < count {
            let piece = output.fileHandleForReading.readData(ofLength: count - buffer.count)
            if piece.isEmpty { break }
            buffer.append(piece)
        }
        return buffer
    }

    func close() {
        if process.isRunning { process.terminate() }
        try? output.fileHandleForReading.close()
    }
}

/// Descompressão de `.xz` pelo framework Compression.
private final class LZMAStream: ByteStream {
    private let handle: FileHandle
    private var stream: UnsafeMutablePointer<compression_stream>
    private var input = Data()
    private var finished = false
    private let inputChunk = 1 << 20

    init(url: URL) throws {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw ImageSource.SourceError.cannotOpen(url)
        }
        self.handle = handle
        stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        let status = compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZMA)
        guard status == COMPRESSION_STATUS_OK else {
            stream.deallocate()
            throw ImageSource.SourceError.decompressionFailed("could not start the LZMA decoder")
        }
        stream.pointee.src_size = 0
        stream.pointee.dst_size = 0
    }

    func read(upTo count: Int) throws -> Data {
        guard !finished else { return Data() }
        var output = Data(count: count)
        var produced = 0

        try output.withUnsafeMutableBytes { destination in
            stream.pointee.dst_ptr = destination.bindMemory(to: UInt8.self).baseAddress!
            stream.pointee.dst_size = count

            while stream.pointee.dst_size > 0 {
                if stream.pointee.src_size == 0 {
                    input = (try? handle.read(upToCount: inputChunk)) ?? Data()
                    if input.isEmpty {
                        // Sem mais entrada: o decodificador precisa saber que o
                        // fluxo acabou para emitir o que resta do buffer.
                        let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                        if status == COMPRESSION_STATUS_END { finished = true }
                        break
                    }
                    input.withUnsafeBytes { source in
                        stream.pointee.src_ptr = source.bindMemory(to: UInt8.self).baseAddress!
                        stream.pointee.src_size = input.count
                    }
                }

                let status = compression_stream_process(stream, 0)
                if status == COMPRESSION_STATUS_END { finished = true; break }
                if status == COMPRESSION_STATUS_ERROR {
                    throw ImageSource.SourceError.decompressionFailed("the .xz stream is corrupt")
                }
            }
            produced = count - stream.pointee.dst_size
        }

        return output.prefix(produced)
    }

    func close() {
        compression_stream_destroy(stream)
        stream.deallocate()
        try? handle.close()
    }
}
