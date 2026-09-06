import Foundation

/// Abre um dispositivo de bloco com autorização do usuário e devolve o
/// descritor já aberto.
///
/// `authopen` é o utilitário do próprio macOS para isso. A forma simples
/// (`-w`, copiando stdin) parece suficiente, mas tem dois defeitos sérios para
/// um app: o pipe intermediário custa uma cópia extra de cada bloco, e se o
/// authopen morre no meio o processo recebe SIGPIPE e **morre junto** — num app
/// com interface, isso é um crash sem mensagem.
///
/// Com `-stdoutpipe` o authopen devolve o descritor por `SCM_RIGHTS` através de
/// um socketpair. Escrevemos direto nele, medimos o progresso com precisão, e
/// uma única autorização serve para gravar e depois reler para verificar.
enum PrivilegedDevice {
    enum OpenError: LocalizedError {
        case authorizationDenied
        case notPermitted(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .authorizationDenied: "Authorization cancelled."
            case .notPermitted(let path): "Access to \(path) was denied by macOS."
            case .failed(let detail): "Could not open the device: \(detail)"
            }
        }
    }

    /// Abre `path` (tipicamente `/dev/rdiskN`) e devolve o descritor.
    /// Com `writable`, o descritor é de leitura e escrita.
    static func open(_ path: String, writable: Bool) throws -> Int32 {
        // Uma escrita num descritor cujo par fechou mataria o processo com
        // SIGPIPE. Queremos o erro EPIPE, que é tratável.
        signal(SIGPIPE, SIG_IGN)

        var pair: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else {
            throw OpenError.failed("socketpair: \(String(cString: strerror(errno)))")
        }
        let ours = pair[0], theirs = pair[1]

        let process = Process()
        process.executableURL = URL(filePath: "/usr/libexec/authopen")
        // -w abre para leitura e escrita; sem ele, só leitura.
        process.arguments = writable ? ["-stdoutpipe", "-w", path] : ["-stdoutpipe", path]
        process.standardOutput = FileHandle(fileDescriptor: theirs, closeOnDealloc: false)
        let errors = Pipe()
        process.standardError = errors

        do {
            try process.run()
        } catch {
            close(ours); close(theirs)
            throw OpenError.failed(error.localizedDescription)
        }
        // O filho já tem sua cópia; a nossa precisa fechar para que o recvmsg
        // veja EOF caso o authopen termine sem enviar nada.
        close(theirs)

        let received = receiveDescriptor(over: ours)
        close(ours)
        process.waitUntilExit()

        guard let descriptor = received else {
            let detail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.contains("not permitted") { throw OpenError.notPermitted(path) }
            if detail.isEmpty { throw OpenError.authorizationDenied }
            throw OpenError.failed(detail)
        }
        return descriptor
    }

    /// Lê a mensagem de controle com o descritor. As macros CMSG_* não existem
    /// em Swift, então o deslocamento é calculado à mão: o cabeçalho `cmsghdr`
    /// tem 12 bytes e o macOS alinha em 4, de modo que o descritor começa
    /// exatamente depois dele.
    private static func receiveDescriptor(over socket: Int32) -> Int32? {
        let headerSize = MemoryLayout<cmsghdr>.size          // 12
        let payloadSize = MemoryLayout<Int32>.size           // 4
        var control = [UInt8](repeating: 0, count: headerSize + payloadSize)
        var byte: UInt8 = 0

        return withUnsafeMutablePointer(to: &byte) { bytePointer -> Int32? in
            var iov = iovec(iov_base: UnsafeMutableRawPointer(bytePointer), iov_len: 1)
            return control.withUnsafeMutableBufferPointer { buffer -> Int32? in
                var message = msghdr()
                message.msg_iov = withUnsafeMutablePointer(to: &iov) { $0 }
                message.msg_iovlen = 1
                message.msg_control = UnsafeMutableRawPointer(buffer.baseAddress!)
                message.msg_controllen = socklen_t(buffer.count)

                guard recvmsg(socket, &message, 0) >= 0, message.msg_controllen >= socklen_t(headerSize + payloadSize)
                else { return nil }

                let header = UnsafeRawPointer(buffer.baseAddress!).assumingMemoryBound(to: cmsghdr.self).pointee
                guard header.cmsg_level == SOL_SOCKET, header.cmsg_type == SCM_RIGHTS else { return nil }

                let descriptor = UnsafeRawPointer(buffer.baseAddress!)
                    .advanced(by: headerSize)
                    .loadUnaligned(as: Int32.self)
                return descriptor >= 0 ? descriptor : nil
            }
        }
    }
}
