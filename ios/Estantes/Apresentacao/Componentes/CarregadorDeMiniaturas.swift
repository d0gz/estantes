import Combine
import UIKit

/// Lê a foto da miniatura de um livro na porta e a entrega reduzida para a lista.
///
/// No banco fica uma foto por livro (a que vai no export), já reduzida para guardar; a lista pede uma menor ainda,
/// pelo `RedutorDeFoto`. As reduzidas ficam num `NSCache`, que é seguro entre threads e se esvazia sozinho quando
/// falta memória. A chave é o livro; o tamanho vai junto, porque a miniatura cresce com o texto grande (pedido
/// maior que o guardado reduz de novo). Criado uma vez na montagem.
///
/// Quando o formulário troca a foto, `esquecer` tira o livro do cache e soma um em `trocas`, que as `MiniaturaDoLivro`
/// observam para pedir de novo (as outras voltam do cache na hora).
final class CarregadorDeMiniaturas: ObservableObject {
    /// Classe porque o `NSCache` só guarda objetos.
    private final class Guardada {
        let imagem: UIImage
        let ladoMaior: Int

        init(imagem: UIImage, ladoMaior: Int) {
            self.imagem = imagem
            self.ladoMaior = ladoMaior
        }
    }

    private let repositorio: BibliotecaRepositorio
    /// `NSUUID`: o `NSCache` só aceita objetos como chave.
    private let cache = NSCache<NSUUID, Guardada>()
    /// Quantas fotos o formulário trocou (só serve de gatilho). Uma conta só para todos os livros: mais simples que
    /// avisar cada miniatura, e as que não mudaram saem do cache sem ler a porta.
    @Published private(set) var trocas = 0

    init(repositorio: BibliotecaRepositorio) {
        self.repositorio = repositorio
    }

    /// A miniatura do livro com o lado maior de até `ladoMaior` pixels, ou `nil` sem foto (ou se a leitura falhar:
    /// na lista, a falta da foto vira a substituta, não um erro).
    func miniatura(doLivro livroId: UUID, ladoMaior: Int) async -> UIImage? {
        if let guardada = cache.object(forKey: livroId as NSUUID), guardada.ladoMaior >= ladoMaior {
            return guardada.imagem
        }
        guard let dados = try? await repositorio.fotoMiniatura(doLivro: livroId),
              // A linha saiu da tela (rolagem rápida): não vale decodificar.
              !Task.isCancelled,
              let imagem = RedutorDeFoto.imagem(dados, ladoMaior: ladoMaior)
        else { return nil }
        let reduzida = UIImage(cgImage: imagem)
        cache.setObject(Guardada(imagem: reduzida, ladoMaior: ladoMaior), forKey: livroId as NSUUID)
        return reduzida
    }

    /// A foto do livro mudou: a próxima leitura vai à porta, e as miniaturas na tela pedem de novo.
    @MainActor
    func esquecer(_ livroId: UUID) {
        cache.removeObject(forKey: livroId as NSUUID)
        trocas += 1
    }
}
