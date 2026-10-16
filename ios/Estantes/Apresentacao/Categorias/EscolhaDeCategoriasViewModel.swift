import Foundation

/// Folha de escolher as categorias de um livro, aberta pelos chips (Detalhe e Estante) e pelo menu de contexto.
/// As marcas ficam num rascunho e só são gravadas no "OK"; "Cancelar" fecha sem gravar.
/// (O PLANO anota a alternativa de gravar a cada toque, como no Lembretes.)
@MainActor
final class EscolhaDeCategoriasViewModel: ObservableObject {
    enum Estado: Equatable {
        case carregando
        /// O livro foi apagado ou o id não existe.
        case naoEncontrado
        /// Todas as categorias, em ordem alfabética.
        case pronto([Categoria])
        case erro(String)
    }

    @Published private(set) var estado: Estado = .carregando
    @Published private(set) var marcadas: Set<UUID> = []
    @Published private(set) var salvando = false
    @Published var mensagemDeErro: String?

    private let livroId: UUID
    /// O livro relido ao abrir: ao gravar, só as categorias mudam nele.
    private var livro: Livro?
    private let repositorio: BibliotecaRepositorio

    init(livroId: UUID, repositorio: BibliotecaRepositorio) {
        self.livroId = livroId
        self.repositorio = repositorio
    }

    func carregar() async {
        do {
            guard let livro = try await repositorio.livro(id: livroId) else {
                estado = .naoEncontrado
                return
            }
            self.livro = livro
            marcadas = livro.categoriaIds
            estado = .pronto(try await repositorio.categorias())
        } catch {
            estado = .erro("Não foi possível carregar as categorias.")
        }
    }

    func alternar(_ categoria: Categoria) {
        if marcadas.contains(categoria.id) {
            marcadas.remove(categoria.id)
        } else {
            marcadas.insert(categoria.id)
        }
    }

    /// A categoria recém-criada pela folha "Nova categoria": entra na lista, na mesma ordem do repositório, e já marcada.
    func incluirNova(_ categoria: Categoria) {
        guard case .pronto(var categorias) = estado else { return }
        categorias.append(categoria)
        categorias.sort { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
        estado = .pronto(categorias)
        marcadas.insert(categoria.id)
    }

    /// Devolve `true` se gravou: a folha então fecha.
    func salvar() async -> Bool {
        guard var livro = livro else { return false }
        livro.categoriaIds = marcadas
        salvando = true
        defer { salvando = false }
        do {
            try await repositorio.salvar(livro)
            self.livro = livro
            return true
        } catch {
            mensagemDeErro = "Não foi possível salvar as categorias."
            return false
        }
    }
}
