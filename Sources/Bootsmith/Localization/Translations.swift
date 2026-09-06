import Foundation

/// Português do Brasil. A chave é o texto em inglês exibido pelo app.
extension L {
    static let ptBR: [String: String] = [
        // MARK: Janela principal
        "Image": "Imagem",
        "Choose an image…": "Escolher imagem…",
        "Drop an ISO here, or choose one": "Solte uma ISO aqui, ou escolha uma",
        "Destination": "Destino",
        "No removable drives connected": "Nenhum dispositivo removível conectado",
        "Connect a USB drive to continue": "Conecte um pendrive para continuar",
        "Refresh": "Atualizar",
        "Write": "Gravar",
        "Cancel": "Cancelar",
        "Verify after writing": "Verificar depois de gravar",
        "Eject when finished": "Ejetar ao terminar",

        // MARK: Boot
        "Boots on": "Inicia em",
        "legacy BIOS and UEFI": "BIOS legado e UEFI",
        "legacy BIOS only": "só BIOS legado",
        "UEFI only": "só UEFI",
        "no boot mode detected": "nenhum modo de boot detectado",
        "This image has no boot signature — it will not start a computer.":
            "Esta imagem não tem assinatura de boot — ela não vai iniciar um computador.",
        "Same stick works on old BIOS machines and new UEFI ones.":
            "O mesmo pendrive funciona em máquinas BIOS antigas e UEFI novas.",

        // MARK: Confirmação
        "Erase %@ and write %@?": "Apagar %@ e gravar %@?",
        "Everything on this device will be lost: %@": "Tudo neste dispositivo será perdido: %@",
        "This device has no mounted volumes.": "Este dispositivo não tem volumes montados.",
        "Erase and write": "Apagar e gravar",

        // MARK: Progresso
        "Writing": "Gravando",
        "Verifying": "Verificando",
        "%@ of %@": "%@ de %@",
        "%@/s": "%@/s",
        "about %@ left": "faltam cerca de %@",
        "Unmounting the device…": "Desmontando o dispositivo…",
        "Do not unplug the drive.": "Não desconecte o pendrive.",

        // MARK: Resultado
        "Done": "Pronto",
        "%@ written and verified": "%@ gravados e verificados",
        "%@ written": "%@ gravados",
        "The drive was ejected — you can unplug it.":
            "O pendrive foi ejetado — pode desconectar.",
        "Verification failed: the drive does not match the image.":
            "A verificação falhou: o pendrive não corresponde à imagem.",
        "Write another": "Gravar outro",

        // MARK: Erros
        "The image is %@ and the device only has %@.": "A imagem tem %@ e o dispositivo só tem %@.",
        "Authorization cancelled — nothing was written.": "Autorização cancelada — nada foi gravado.",
        "macOS blocked access to %@. Grant Full Disk Access to Bootsmith in System Settings › Privacy & Security, then reopen the app.":
            "O macOS bloqueou o acesso a %@. Conceda Acesso Total ao Disco ao Bootsmith em Ajustes do Sistema › Privacidade e Segurança e reabra o app.",
        "The write failed: %@": "A gravação falhou: %@",
        "Only %@ of %@ were written — the drive may have been removed.":
            "Apenas %@ de %@ foram gravados — o dispositivo pode ter sido removido.",
        "Could not read the image.": "Não foi possível ler a imagem.",

        // MARK: Imagens comprimidas
        "%@ compressed": "%@ comprimidos",
        "%@ compressed · final size unknown": "%@ comprimidos · tamanho final desconhecido",
        "Decompression failed: %@": "A descompressão falhou: %@",

        // MARK: Checksum
        "Verify checksum": "Conferir checksum",
        "Paste a SHA-256, or the contents of SHA256SUMS":
            "Cole um SHA-256, ou o conteúdo do arquivo SHA256SUMS",
        "Check": "Conferir",
        "Matches": "Confere",
        "Does not match — do not use this image": "Não confere — não use esta imagem",
        "No SHA-256 found for this file": "Nenhum SHA-256 encontrado para este arquivo",

        // MARK: Restaurar o pendrive
        "Restore drive": "Restaurar pendrive",
        "Erase as %@": "Apagar como %@",
        "Erase %@ as %@?": "Apagar %@ como %@?",
        "Erase": "Apagar",
        "Everything on the drive will be lost, including the image you wrote.":
            "Tudo no pendrive será perdido, inclusive a imagem que você gravou.",
        "Erasing the drive…": "Apagando o pendrive…",
        "Drive restored as %@": "Pendrive restaurado como %@",
        "You can use it in Finder again.": "Você pode usá-lo no Finder de novo.",

        // MARK: Avisos de dispositivo
        "too small": "pequeno demais",
        "The image does not fit on this device.": "A imagem não cabe neste dispositivo.",
        "large disk": "disco grande",
        "This looks like an external disk rather than a USB stick.":
            "Isto parece um disco externo, não um pendrive.",

        // MARK: Ajustes e Sobre
        "General": "Geral",
        "Language": "Idioma",
        "System": "Sistema",
        "About Bootsmith": "Sobre o Bootsmith",
        "Bootable USB drives for BIOS and UEFI.": "Pendrives bootáveis para BIOS e UEFI.",
        "Version %@": "Versão %@",
        "Developer": "Desenvolvedor",
        "Source": "Código",
        "Free and open source under the MIT license.": "Livre e de código aberto sob a licença MIT.",
    ]
}
