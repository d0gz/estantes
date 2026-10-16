import Foundation

/// Os livros de uma estante, agrupados por prateleira (`AgrupamentoPorPrateleira`, no Domínio).
@MainActor
final class EstanteViewModel: ObservableObject {
    enum Estado: Equatable {
        case carregando
        case vazia
        case pronta([GrupoDePrateleira])
        case erro(String)
    }

    let estante: Estante
    @Published private(set) var estado: Estado = .carregando
    /// Todas as categorias, em ordem alfabética: os livros guardam só os ids, e os chips precisam de nome e cor.
    @Published private(set) var todasAsCategorias: [Categoria] = []

    private let repositorio: BibliotecaRepositorio

    init(estante: Estante, repositorio: BibliotecaRepositorio) {
        self.estante = estante
        self.repositorio = repositorio
    }

    func carregar() async {
        do {
            let livros = try await repositorio.livros(naEstante: estante.id)
            todasAsCategorias = try await repositorio.categorias()
            estado = livros.isEmpty ? .vazia : .pronta(AgrupamentoPorPrateleira.agrupar(livros))
        } catch {
            estado = .erro("Não foi possível carregar os livros.")
        }
    }

    /// As categorias do livro, na ordem alfabética (chips da linha).
    func categorias(de livro: Livro) -> [Categoria] {
        todasAsCategorias.comIds(livro.categoriaIds)
    }

    /// Linha de baixo do livro na lista: autores e ano ("Silva, José Afonso da · 2014").
    static func linhaSecundaria(_ livro: Livro) -> String? {
        let partes = [
            livro.autores.isEmpty ? nil : livro.autores.joined(separator: "; "),
            livro.ano.map(String.init),
        ].compactMap { $0 }
        return partes.isEmpty ? nil : partes.joined(separator: " · ")
    }

    /// Cabeçalho da prateleira com a contagem ("Caixa azul · 2"): ajuda a conferir a estante física.
    static func cabecalho(_ grupo: GrupoDePrateleira) -> String {
        "\(nomeDaPrateleira(grupo)) · \(grupo.livros.count)"
    }

    /// A etiqueta, ou "Sem prateleira" para os livros sem etiqueta.
    static func nomeDaPrateleira(_ grupo: GrupoDePrateleira) -> String {
        grupo.prateleira ?? "Sem prateleira"
    }
}
