import Foundation

/// Porta da biblioteca do usuário: o Domínio declara do que precisa, e a camada Dados implementa
/// (Core Data no app; uma versão em memória nos testes e previews).
///
/// `async throws`: o Core Data trabalha num contexto em segundo plano e gravar em disco pode falhar;
/// os ViewModels (`@MainActor`) esperam com `await` sem travar a tela.
/// Um repositório só, e não um por entidade: a importação "substituir" troca tudo numa transação.
protocol BibliotecaRepositorio {
    // MARK: Estantes

    func estantes() async throws -> [Estante]
    /// Cria ou atualiza (pelo `id`).
    func salvar(_ estante: Estante) async throws
    func quantidadeDeLivros(naEstante estanteId: UUID) async throws -> Int
    /// Apaga a estante. Com `destino`, os livros são movidos para lá antes; sem ele, vão junto (cascata).
    func apagarEstante(id: UUID, moverLivrosPara destino: UUID?) async throws

    // MARK: Livros

    func livros(naEstante estanteId: UUID) async throws -> [Livro]
    /// Todos os livros, para montar o índice da busca ao abrir o app.
    func todosOsLivros() async throws -> [Livro]
    func livro(id: UUID) async throws -> Livro?
    /// Cria ou atualiza (pelo `id`), com o sumário substituído em bloco.
    func salvar(_ livro: Livro) async throws
    func apagarLivro(id: UUID) async throws
    /// Etiquetas de prateleira já usadas na estante, para sugerir ao usuário.
    func prateleiras(naEstante estanteId: UUID) async throws -> [String]
    func fotoCapa(doLivro livroId: UUID) async throws -> Data?
    /// `nil` remove a foto.
    func salvarFotoCapa(_ foto: Data?, doLivro livroId: UUID) async throws

    // MARK: Categorias

    func categorias() async throws -> [Categoria]
    /// Cria ou atualiza (pelo `id`).
    func salvar(_ categoria: Categoria) async throws
    /// Os livros só perdem a etiqueta (nullify).
    func apagarCategoria(id: UUID) async throws
}
