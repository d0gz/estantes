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

    private let repositorio: BibliotecaRepositorio

    init(estante: Estante, repositorio: BibliotecaRepositorio) {
        self.estante = estante
        self.repositorio = repositorio
    }

    func carregar() async {
        do {
            let livros = try await repositorio.livros(naEstante: estante.id)
            estado = livros.isEmpty ? .vazia : .pronta(AgrupamentoPorPrateleira.agrupar(livros))
        } catch {
            estado = .erro("Não foi possível carregar os livros.")
        }
    }

    /// Linha de baixo do livro na lista: autores e ano ("Silva, José Afonso da · 2014").
    static func linhaSecundaria(_ livro: Livro) -> String? {
        let partes = [
            livro.autores.isEmpty ? nil : livro.autores.joined(separator: "; "),
            livro.ano.map(String.init),
        ].compactMap { $0 }
        return partes.isEmpty ? nil : partes.joined(separator: " · ")
    }
}
