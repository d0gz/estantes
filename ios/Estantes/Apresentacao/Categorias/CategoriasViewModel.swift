import Foundation

/// Uma categoria como a tela de gerenciar a mostra: a categoria e em quantos livros ela está.
/// Na Apresentação, como o `EstanteResumo`: a contagem é um dado da tela, não da `Categoria`.
struct CategoriaResumo: Identifiable, Equatable {
    let categoria: Categoria
    let quantidadeDeLivros: Int

    var id: UUID { categoria.id }
}

/// O que a confirmação de "apagar categoria" mostra, lido do banco na hora do pedido.
struct ExclusaoDeCategoria: Identifiable, Equatable {
    let categoria: Categoria
    let quantidadeDeLivros: Int

    var id: UUID { categoria.id }
}

/// Estado da tela de gerenciar categorias (aberta pelo menu ⋯ do Inicio) e a ação de apagar.
/// Criar e editar ficam no `CategoriaFormularioViewModel`, numa folha; depois dela a tela chama `carregar()`.
@MainActor
final class CategoriasViewModel: ObservableObject {
    enum Estado: Equatable {
        case carregando
        case vazio
        case pronto([CategoriaResumo])
        case erro(String)
    }

    @Published private(set) var estado: Estado = .carregando
    /// Falha ao gravar. Fica separada do `estado`: a lista continua na tela e um alerta avisa.
    @Published var mensagemDeErro: String?

    private let repositorio: BibliotecaRepositorio

    init(repositorio: BibliotecaRepositorio) {
        self.repositorio = repositorio
    }

    /// Duas leituras (as categorias, já em ordem alfabética, e as contagens), não uma por categoria.
    func carregar() async {
        do {
            let quantidades = try await repositorio.quantidadeDeLivrosPorCategoria()
            let resumos = try await repositorio.categorias().map {
                CategoriaResumo(categoria: $0, quantidadeDeLivros: quantidades[$0.id, default: 0])
            }
            estado = resumos.isEmpty ? .vazio : .pronto(resumos)
        } catch {
            estado = .erro("Não foi possível carregar as categorias.")
        }
    }

    /// Prepara a confirmação. A quantidade é relida do banco (e não tirada da lista): numa ação destrutiva, o
    /// número mostrado precisa ser o de agora (como no "apagar estante").
    func pedidoDeExclusao(de categoria: Categoria) async -> ExclusaoDeCategoria? {
        do {
            let quantidades = try await repositorio.quantidadeDeLivrosPorCategoria()
            return ExclusaoDeCategoria(categoria: categoria, quantidadeDeLivros: quantidades[categoria.id, default: 0])
        } catch {
            mensagemDeErro = "Não foi possível preparar a exclusão da categoria."
            return nil
        }
    }

    /// Os livros só perdem a etiqueta (nullify, no repositório).
    func apagar(_ categoria: Categoria) async {
        do {
            try await repositorio.apagarCategoria(id: categoria.id)
        } catch {
            mensagemDeErro = "Não foi possível apagar a categoria."
        }
        await carregar()
    }
}
