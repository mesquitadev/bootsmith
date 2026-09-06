import Foundation

/// Avisa quando um dispositivo removível aparece ou some.
///
/// O macOS notifica montagem e desmontagem de *volumes*, mas um pendrive recém
/// gravado com uma ISO não monta volume nenhum — ele existe como disco e some
/// dessas notificações. Por isso a checagem é uma varredura curta e periódica:
/// `diskutil list` custa poucos milissegundos e nunca erra o estado real.
@MainActor
final class DriveWatcher {
    private var timer: Timer?
    private var lastSignature: String = ""

    /// Chamado só quando o conjunto de dispositivos muda de fato, para não
    /// redesenhar a lista a cada dois segundos.
    var onChange: (([Drive]) -> Void)?

    func start() {
        stop()
        check()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        // .common para continuar rodando enquanto um menu está aberto.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let drives = (try? DriveScanner().scan()) ?? []
        let signature = drives.map { "\($0.id):\($0.size):\($0.volumes.joined(separator: ","))" }
            .joined(separator: "|")
        guard signature != lastSignature else { return }
        lastSignature = signature
        onChange?(drives)
    }
}
