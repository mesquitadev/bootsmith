import Foundation
import CryptoKit

/// Grava uma imagem num disco inteiro e confere o resultado.
///
/// Escrever em `/dev/rdiskN` esbarra em duas barreiras independentes: as
/// permissões Unix (o nó pertence a root) e o TCC, que desde o macOS 13 protege
/// volumes removíveis. Elevar com `osascript … with administrator privileges`
/// resolve a primeira e falha na segunda — o processo elevado roda num contexto
/// próprio e não herda o Acesso Total ao Disco concedido ao app.
///
/// `PrivilegedDevice` resolve as duas de uma vez, e devolve um descritor de
/// leitura e escrita: a mesma autorização cobre a gravação e a releitura da
/// verificação.
struct Flasher: Sendable {
    enum FlashError: LocalizedError {
        case imageLargerThanDrive(image: Int64, drive: Int64)
        case authorizationDenied
        case accessDenied(String)
        case writeFailed(String)
        case shortWrite(written: Int64, expected: Int64)

        var errorDescription: String? { compose { $0 } }

        @MainActor
        var localized: String { compose { L.t($0) } }

        private func compose(_ translate: (String) -> String) -> String {
            switch self {
            case .imageLargerThanDrive(let image, let drive):
                let i = ByteCountFormatter.string(fromByteCount: image, countStyle: .file)
                let d = ByteCountFormatter.string(fromByteCount: drive, countStyle: .file)
                return String(format: translate("The image is %@ and the device only has %@."), i, d)
            case .authorizationDenied:
                return translate("Authorization cancelled — nothing was written.")
            case .accessDenied(let device):
                return String(format: translate("macOS blocked access to %@. Grant Full Disk Access to Bootsmith in System Settings › Privacy & Security, then reopen the app."), device)
            case .writeFailed(let detail):
                return String(format: translate("The write failed: %@"), detail)
            case .shortWrite(let written, let expected):
                let w = ByteCountFormatter.string(fromByteCount: written, countStyle: .file)
                let e = ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)
                return String(format: translate("Only %@ of %@ were written — the drive may have been removed."), w, e)
            }
        }
    }

    struct Progress: Sendable {
        var bytesWritten: Int64
        var totalBytes: Int64
        var bytesPerSecond: Double

        var fraction: Double {
            totalBytes > 0 ? min(1, Double(bytesWritten) / Double(totalBytes)) : 0
        }

        var remaining: TimeInterval? {
            guard bytesPerSecond > 0, bytesWritten < totalBytes else { return nil }
            return Double(totalBytes - bytesWritten) / bytesPerSecond
        }
    }

    let image: DiskImage
    let drive: Drive

    /// 4 MiB, o mesmo bloco que o `dd` usa por convenção em pendrives.
    private static let chunkSize = 4 * 1024 * 1024

    /// O nó bruto (`/dev/rdiskN`) só aceita leituras e escritas alinhadas ao
    /// setor: uma escrita de tamanho arbitrário é rejeitada com EINVAL. Como a
    /// imagem pode terminar no meio de um setor, o último bloco é completado
    /// com zeros — o espaço além da imagem é área livre do dispositivo.
    private static let sectorSize = 512

    private static func roundedUpToSector(_ value: Int) -> Int {
        (value + sectorSize - 1) / sectorSize * sectorSize
    }

    /// Grava e, se `verify`, relê o dispositivo comparando digests.
    /// Devolve `true` quando a verificação passou (ou não foi pedida).
    func flash(
        verify: Bool,
        onProgress: @Sendable @escaping (Progress) -> Void,
        onVerifyProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> Bool {
        guard image.size <= drive.size else {
            throw FlashError.imageLargerThanDrive(image: image.size, drive: drive.size)
        }

        // Com um volume montado o kernel recusa a escrita no dispositivo inteiro.
        _ = try? Shell.run("/usr/sbin/diskutil", ["unmountDisk", drive.deviceNode])

        let descriptor: Int32
        do {
            descriptor = try PrivilegedDevice.open(drive.rawDeviceNode, writable: true)
        } catch PrivilegedDevice.OpenError.authorizationDenied {
            throw FlashError.authorizationDenied
        } catch PrivilegedDevice.OpenError.notPermitted {
            throw FlashError.accessDenied(drive.rawDeviceNode)
        } catch {
            throw FlashError.writeFailed(error.localizedDescription)
        }
        defer { close(descriptor) }

        // A leitura passa pelo descompressor quando a imagem é comprimida; para
        // uma imagem crua o fluxo é a própria leitura do arquivo.
        let source = try ImageSource.open(image.url, format: image.format)
        defer { source.close() }

        var written: Int64 = 0
        var imageDigest = SHA256()
        let started = Date()
        var lastReport = Date.distantPast

        while true {
            let chunk = try source.read(upTo: Self.chunkSize)
            if chunk.isEmpty { break }
            imageDigest.update(data: chunk)

            var block = chunk
            let aligned = Self.roundedUpToSector(chunk.count)
            if aligned > chunk.count {
                block.append(contentsOf: [UInt8](repeating: 0, count: aligned - chunk.count))
            }
            try Self.writeFully(block, to: descriptor)
            written += Int64(chunk.count)

            // Reportar a cada bloco inundaria a UI; 4 vezes por segundo basta.
            if Date().timeIntervalSince(lastReport) > 0.25 {
                lastReport = Date()
                let elapsed = Date().timeIntervalSince(started)
                onProgress(Progress(bytesWritten: written, totalBytes: image.size,
                                    bytesPerSecond: elapsed > 0 ? Double(written) / elapsed : 0))
            }
        }

        // Com tamanho estimado (bzip2), o total só se conhece ao final.
        guard !image.sizeIsExact || written == image.size else {
            throw FlashError.shortWrite(written: written, expected: image.size)
        }
        fsync(descriptor)

        let elapsed = Date().timeIntervalSince(started)
        onProgress(Progress(bytesWritten: image.size, totalBytes: image.size,
                            bytesPerSecond: elapsed > 0 ? Double(written) / elapsed : 0))

        guard verify else { return true }
        return try Self.verify(descriptor: descriptor, expecting: imageDigest.finalize(),
                               size: written, onProgress: onVerifyProgress)
    }

    /// Um `write` pode gravar menos que o pedido; o laço garante o bloco inteiro.
    private static func writeFully(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let result = write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if result < 0 {
                    if errno == EINTR { continue }
                    throw FlashError.writeFailed(String(cString: strerror(errno)))
                }
                if result == 0 { throw FlashError.writeFailed("device stopped accepting data") }
                offset += result
            }
        }
    }

    // Internal, e não private, para que o teste possa rodar a verificação
    // isolada contra um dispositivo corrompido de propósito.
    /// Relê do dispositivo a mesma quantidade de bytes da imagem e compara os
    /// digests. Um pendrive pode aceitar toda a escrita e ainda assim conter
    /// lixo — flash gasto, cabo ruim, adaptador barato. Descobrir aqui custa
    /// minutos; descobrir na frente do servidor custa uma viagem.
    static func verify(
        descriptor: Int32,
        expecting expected: SHA256Digest,
        size: Int64,
        onProgress: @Sendable (Double) -> Void
    ) throws -> Bool {
        guard lseek(descriptor, 0, SEEK_SET) == 0 else {
            throw FlashError.writeFailed("could not rewind the device")
        }
        var digest = SHA256()
        var read: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: chunkSize + sectorSize)

        while read < size {
            // A leitura também precisa ser alinhada; o excedente do último
            // setor é descartado antes de entrar no digest.
            let remaining = Int(min(Int64(chunkSize), size - read))
            let wanted = roundedUpToSector(remaining)
            let got = buffer.withUnsafeMutableBytes { Foundation.read(descriptor, $0.baseAddress, wanted) }
            if got < 0 {
                if errno == EINTR { continue }
                throw FlashError.writeFailed(String(cString: strerror(errno)))
            }
            if got == 0 { break }
            let useful = min(got, remaining)
            digest.update(data: Data(buffer[0..<useful]))
            read += Int64(useful)
            onProgress(Double(read) / Double(size))
        }

        guard read == size else { return false }
        return digest.finalize() == expected
    }

    static func eject(_ drive: Drive) {
        _ = try? Shell.run("/usr/sbin/diskutil", ["eject", drive.deviceNode])
    }
}
