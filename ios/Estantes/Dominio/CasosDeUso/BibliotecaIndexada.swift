import Foundation

/// O repositório da biblioteca com o índice da busca junto: repassa cada chamada à `base` e, depois de
/// uma gravação bem-sucedida, atualiza o `MotorDeBusca` (padrão Decorador). Quem grava não sabe que
/// existe um índice, então nenhum ViewModel precisa lembrar de avisá-lo.
///
/// `actor` porque o motor é estado que muda: duas gravações e uma busca ao mesmo tempo poderiam deixar
/// o índice pela metade. O actor deixa entrar uma chamada de cada vez.
actor BibliotecaIndexada: BibliotecaRepositorio {
    private let base: BibliotecaRepositorio
    /// A montagem do índice, guardada como `Task` para que quem chega durante ela espere a mesma
    /// montagem em vez de começar outra: num `await`, o actor deixa outra chamada entrar (reentrância).
    private var montagem: Task<MotorDeBusca, Error>?
    private var motor: MotorDeBusca?

    init(base: BibliotecaRepositorio) {
        self.base = base
    }

    // MARK: - Busca

    /// Monta o índice com todos os livros e categorias. Chamar de novo não faz nada; se a leitura
    /// falhar, a próxima chamada tenta outra vez.
    func preparar() async throws {
        _ = try await motorPronto()
    }

    /// A busca do `MotorDeBusca`; espera a montagem do índice se ela ainda não terminou.
    func buscar(_ texto: String, filtro: FiltroBusca = FiltroBusca(), corrigir: Bool = true) async throws -> RespostaBusca {
        try await motorPronto().buscar(texto, filtro: filtro, corrigir: corrigir)
    }

    private func motorPronto() async throws -> MotorDeBusca {
        if let motor = motor { return motor }
        let tarefa = montagem ?? Task { [base] in
            MotorDeBusca(livros: try await base.todosOsLivros(), categorias: try await base.categorias())
        }
        montagem = tarefa
        do {
            let montado = try await tarefa.value
            if motor == nil { motor = montado }
            return motor ?? montado
        } catch {
            montagem = nil
            throw error
        }
    }

    /// Aplica a mudança ao índice depois de uma gravação bem-sucedida. Índice ainda não montado: nada a
    /// fazer, a montagem vai ler o banco já gravado. Montagem em andamento: espera e aplica por cima (ela
    /// pode ter lido o banco antes da gravação); repetir `atualizar` ou `remover` dá o mesmo índice.
    private func atualizarIndice(_ mudanca: (inout MotorDeBusca) -> Void) async {
        if motor == nil, montagem != nil {
            // Se a montagem falhar, o próximo `preparar` lê tudo de novo, com esta gravação.
            _ = try? await motorPronto()
        }
        guard motor != nil else { return }
        mudanca(&motor!)
    }

    /// Depois de criar, renomear ou apagar uma categoria: o motor precisa da lista inteira, relida.
    /// Se a releitura falhar, a gravação já deu certo e não deve virar erro: o índice é descartado e a
    /// próxima busca monta tudo de novo.
    private func atualizarCategoriasDoIndice() async {
        do {
            let categorias = try await base.categorias()
            await atualizarIndice { $0.atualizar(categorias: categorias) }
        } catch {
            motor = nil
            montagem = nil
        }
    }

    // MARK: - Estantes

    func estantes() async throws -> [Estante] {
        try await base.estantes()
    }

    func salvar(_ estante: Estante) async throws {
        try await base.salvar(estante)
    }

    func quantidadeDeLivros(naEstante estanteId: UUID) async throws -> Int {
        try await base.quantidadeDeLivros(naEstante: estanteId)
    }

    func apagarEstante(id: UUID, moverLivrosPara destino: UUID?) async throws {
        // Lidos antes: sem destino, a cascata apaga os livros e não há mais como saber quem estava lá.
        // Com destino, as cópias lidas ganham a estante nova em vez de serem relidas: uma releitura que
        // falhasse depois de apagar acusaria erro numa exclusão que deu certo.
        let livros = try await base.livros(naEstante: id)
        try await base.apagarEstante(id: id, moverLivrosPara: destino)
        await atualizarIndice { motor in
            for var livro in livros {
                if let destino = destino {
                    livro.estanteId = destino
                    motor.atualizar(livro)
                } else {
                    motor.remover(livroId: livro.id)
                }
            }
        }
    }

    // MARK: - Livros

    func livros(naEstante estanteId: UUID) async throws -> [Livro] {
        try await base.livros(naEstante: estanteId)
    }

    func todosOsLivros() async throws -> [Livro] {
        try await base.todosOsLivros()
    }

    func livro(id: UUID) async throws -> Livro? {
        try await base.livro(id: id)
    }

    func salvar(_ livro: Livro) async throws {
        try await base.salvar(livro)
        await atualizarIndice { $0.atualizar(livro) }
    }

    func apagarLivro(id: UUID) async throws {
        try await base.apagarLivro(id: id)
        await atualizarIndice { $0.remover(livroId: id) }
    }

    func prateleiras(naEstante estanteId: UUID) async throws -> [String] {
        try await base.prateleiras(naEstante: estanteId)
    }

    func fotoMiniatura(doLivro livroId: UUID) async throws -> Data? {
        try await base.fotoMiniatura(doLivro: livroId)
    }

    func salvarFotoMiniatura(_ foto: Data?, doLivro livroId: UUID) async throws {
        try await base.salvarFotoMiniatura(foto, doLivro: livroId)
    }

    // MARK: - Categorias

    func categorias() async throws -> [Categoria] {
        try await base.categorias()
    }

    func salvar(_ categoria: Categoria) async throws {
        try await base.salvar(categoria)
        await atualizarCategoriasDoIndice()
    }

    func apagarCategoria(id: UUID) async throws {
        try await base.apagarCategoria(id: id)
        await atualizarCategoriasDoIndice()
    }

    func quantidadeDeLivrosPorCategoria() async throws -> [UUID: Int] {
        try await base.quantidadeDeLivrosPorCategoria()
    }
}
