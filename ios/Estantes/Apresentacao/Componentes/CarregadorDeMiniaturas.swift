import ImageIO
import UIKit

/// Lê a foto da miniatura de um livro na porta e a entrega reduzida para a lista.
///
/// No banco fica só a foto original (uma por livro, o que vai no export). A redução usa o ImageIO, que decodifica
/// direto no tamanho pedido: `UIImage(data:)` abriria a foto inteira (uma de 12 MP ocupa ~48 MB decodificada) só
/// para depois encolher. As reduzidas ficam num `NSCache`, que é seguro entre threads e se esvazia sozinho quando
/// falta memória; a chave é só o livro, porque a lista usa um tamanho só. Criado uma vez na montagem.
final class CarregadorDeMiniaturas {
    private let repositorio: BibliotecaRepositorio
    /// `NSUUID`: o `NSCache` só aceita objetos como chave.
    private let cache = NSCache<NSUUID, UIImage>()

    init(repositorio: BibliotecaRepositorio) {
        self.repositorio = repositorio
    }

    /// A miniatura do livro com o lado maior de até `ladoMaior` pixels, ou `nil` sem foto (ou se a leitura falhar:
    /// na lista, a falta da foto vira a substituta, não um erro).
    func miniatura(doLivro livroId: UUID, ladoMaior: Int) async -> UIImage? {
        if let guardada = cache.object(forKey: livroId as NSUUID) { return guardada }
        guard let dados = try? await repositorio.fotoMiniatura(doLivro: livroId),
              let reduzida = Self.reduzir(dados, ladoMaior: ladoMaior)
        else { return nil }
        cache.setObject(reduzida, forKey: livroId as NSUUID)
        return reduzida
    }

    /// Tira o livro do cache: chamar depois de trocar ou apagar a foto, para a lista não mostrar a antiga.
    func esquecer(livroId: UUID) {
        cache.removeObject(forKey: livroId as NSUUID)
    }

    private static func reduzir(_ dados: Data, ladoMaior: Int) -> UIImage? {
        // Sem cache da imagem cheia: ela seria decodificada e guardada só para ser jogada fora.
        let semCache = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let fonte = CGImageSourceCreateWithData(dados as CFData, semCache) else { return nil }
        let opcoes = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, // ignora a miniatura embutida no JPEG (pode ser pequena)
            kCGImageSourceCreateThumbnailWithTransform: true,   // aplica a orientação EXIF (foto de celular "deitada")
            kCGImageSourceShouldCacheImmediately: true,         // decodifica aqui, fora da fila principal
            kCGImageSourceThumbnailMaxPixelSize: ladoMaior,
        ] as CFDictionary
        guard let imagem = CGImageSourceCreateThumbnailAtIndex(fonte, 0, opcoes) else { return nil }
        return UIImage(cgImage: imagem)
    }
}
