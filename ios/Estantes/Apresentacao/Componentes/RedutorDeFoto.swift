import ImageIO
import UniformTypeIdentifiers

/// Reduz fotos com o ImageIO, que decodifica direto no tamanho pedido: abrir a foto inteira (uma de 12 MP ocupa
/// ~48 MB decodificada) só para depois encolher seria desperdício. Serve à miniatura na lista
/// (`CarregadorDeMiniaturas`) e à foto que se guarda (`paraGuardar`).
enum RedutorDeFoto {
    /// A foto guardada serve para mostrar, não para ler: a de alta qualidade só é usada (na Fase 3, o OCR roda na
    /// resolução máxima da câmera) e depois descartada. 1200 px dão folga para uma vista ampliada; ~150 KB por livro.
    static let ladoMaiorGuardado = 1200
    static let qualidadeGuardada = 0.8

    /// A foto pronta para o banco: JPEG com o lado maior de até `ladoMaiorGuardado` pixels. `nil` se não for imagem.
    static func paraGuardar(_ dados: Data) -> Data? {
        guard let imagem = imagem(dados, ladoMaior: ladoMaiorGuardado) else { return nil }
        let saida = NSMutableData()
        guard let destino = CGImageDestinationCreateWithData(saida, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let opcoes = [kCGImageDestinationLossyCompressionQuality: qualidadeGuardada] as CFDictionary
        CGImageDestinationAddImage(destino, imagem, opcoes)
        guard CGImageDestinationFinalize(destino) else { return nil }
        return saida as Data
    }

    /// A imagem com o lado maior de até `ladoMaior` pixels, já na orientação certa.
    static func imagem(_ dados: Data, ladoMaior: Int) -> CGImage? {
        // Sem cache da imagem cheia: ela seria decodificada e guardada só para ser jogada fora.
        let semCache = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let fonte = CGImageSourceCreateWithData(dados as CFData, semCache) else { return nil }
        let opcoes = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, // ignora a miniatura embutida no JPEG (pode ser pequena)
            kCGImageSourceCreateThumbnailWithTransform: true,   // aplica a orientação EXIF (foto de celular "deitada")
            kCGImageSourceShouldCacheImmediately: true,         // decodifica aqui, fora da fila principal
            kCGImageSourceThumbnailMaxPixelSize: ladoMaior,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(fonte, 0, opcoes)
    }
}
