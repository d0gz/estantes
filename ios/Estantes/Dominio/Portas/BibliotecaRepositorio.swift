import Foundation

/// Porta da biblioteca do usuário: o Domínio declara do que precisa, e a camada Dados implementa
/// (Core Data no app; uma versão em memória nos testes e previews).
///
/// `async throws`: o Core Data trabalha num contexto em segundo plano e gravar em disco pode falhar;
/// os ViewModels (`@MainActor`) esperam com `await` sem travar a tela.
/// Um repositório só, e não um por entidade: a importação "substituir" troca tudo numa transação.
///
/// Ids que não existem:
/// - **apagar** algo que não existe não faz nada (apagar duas vezes dá o mesmo resultado);
/// - **ler** devolve `nil`, lista vazia ou zero;
/// - **gravar** apontando para algo que não existe (estante do livro, categoria, livro da foto) lança erro,
///   porque o dado seria perdido ou ficaria solto.
protocol BibliotecaRepositorio {
    // MARK: Estantes

    func estantes() async throws -> [Estante]
    /// Cria ou atualiza (pelo `id`).
    func salvar(_ estante: Estante) async throws
    func quantidadeDeLivros(naEstante estanteId: UUID) async throws -> Int
    /// Apaga a estante. Com `destino`, os livros são movidos para lá antes; sem ele, vão junto (cascata).
    /// Lança erro se o `destino` não existir ou for a própria estante, sem apagar nada.
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
    /// A foto que identifica o livro na lista: livre (capa, folha de rosto…), escolhida pelo usuário.
    func fotoMiniatura(doLivro livroId: UUID) async throws -> Data?
    /// `nil` remove a foto.
    func salvarFotoMiniatura(_ foto: Data?, doLivro livroId: UUID) async throws

    // MARK: Categorias

    func categorias() async throws -> [Categoria]
    /// Cria ou atualiza (pelo `id`).
    func salvar(_ categoria: Categoria) async throws
    /// Os livros só perdem a etiqueta (nullify).
    func apagarCategoria(id: UUID) async throws
    /// Quantos livros têm cada categoria. Toda categoria aparece, com 0 se não estiver em nenhum livro.
    func quantidadeDeLivrosPorCategoria() async throws -> [UUID: Int]

    // MARK: Biblioteca inteira

    /// Deixa a biblioteca igual ao `conteudo`, de uma vez: ou grava tudo, ou nada muda (importação, 21/10).
    /// O que não está no conteúdo é apagado; o livro que continua (mesmo id) mantém a foto, que o arquivo
    /// não traz. Livro que aponta para estante ou categoria fora do conteúdo lança erro, sem gravar nada.
    func substituirBiblioteca(por conteudo: ConteudoDaBiblioteca) async throws
}
