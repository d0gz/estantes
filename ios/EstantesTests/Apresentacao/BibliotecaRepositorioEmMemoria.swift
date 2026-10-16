import Foundation
@testable import Estantes

/// Implementação falsa da porta para os testes dos ViewModels: dicionários em memória e
/// um interruptor para simular falhas. Segue o contrato da porta (ids inexistentes, cascata, mover).
final class BibliotecaRepositorioEmMemoria: BibliotecaRepositorio {
    struct FalhaSimulada: Error {}

    var estantesGuardadas: [UUID: Estante] = [:]
    var livrosGuardados: [UUID: Livro] = [:]
    var categoriasGuardadas: [UUID: Categoria] = [:]
    var fotos: [UUID: Data] = [:]
    /// Quantas vezes `fotoMiniatura` foi chamada (para conferir o cache do `CarregadorDeMiniaturas`).
    private(set) var leiturasDeFoto = 0
    /// Quantas vezes `salvarFotoMiniatura` foi chamada (para conferir que o formulário só grava foto mudada).
    private(set) var gravacoesDeFoto = 0

    /// Ligados, fazem as leituras ou as gravações lançarem `FalhaSimulada`.
    var falharAoLer = false
    var falharAoGravar = false
    /// Ligado, só a gravação da foto falha (o livro grava): o formulário grava os dois em passos separados.
    var falharAoGravarFoto = false
    /// Roda no meio da leitura das prateleiras, antes da resposta: simula o usuário mexendo na tela enquanto espera.
    var durantePrateleiras: (@MainActor () async -> Void)?

    init(estantes: [Estante] = [], livros: [Livro] = []) {
        for estante in estantes { estantesGuardadas[estante.id] = estante }
        for livro in livros { livrosGuardados[livro.id] = livro }
    }

    private func lendo() throws {
        if falharAoLer { throw FalhaSimulada() }
    }

    private func gravando() throws {
        if falharAoGravar { throw FalhaSimulada() }
    }

    // MARK: Estantes

    func estantes() async throws -> [Estante] {
        try lendo()
        return estantesGuardadas.values.sorted { ($0.criadaEm, $0.id.uuidString) < ($1.criadaEm, $1.id.uuidString) }
    }

    func salvar(_ estante: Estante) async throws {
        try gravando()
        estantesGuardadas[estante.id] = estante
    }

    func quantidadeDeLivros(naEstante estanteId: UUID) async throws -> Int {
        try lendo()
        return livrosGuardados.values.filter { $0.estanteId == estanteId }.count
    }

    func apagarEstante(id: UUID, moverLivrosPara destino: UUID?) async throws {
        try gravando()
        if destino == id { throw ErroPersistencia.destinoInvalido(id) }
        guard estantesGuardadas[id] != nil else { return }
        if let destino = destino, estantesGuardadas[destino] == nil {
            throw ErroPersistencia.estanteNaoEncontrada(destino)
        }
        for livro in livrosGuardados.values where livro.estanteId == id {
            if let destino = destino {
                livrosGuardados[livro.id]?.estanteId = destino
            } else {
                livrosGuardados[livro.id] = nil
            }
        }
        estantesGuardadas[id] = nil
    }

    // MARK: Livros

    func livros(naEstante estanteId: UUID) async throws -> [Livro] {
        try lendo()
        return livrosGuardados.values.filter { $0.estanteId == estanteId }.sorted { $0.adicionadoEm < $1.adicionadoEm }
    }

    func todosOsLivros() async throws -> [Livro] {
        try lendo()
        return Array(livrosGuardados.values)
    }

    func livro(id: UUID) async throws -> Livro? {
        try lendo()
        return livrosGuardados[id]
    }

    func salvar(_ livro: Livro) async throws {
        try gravando()
        guard estantesGuardadas[livro.estanteId] != nil else {
            throw ErroPersistencia.estanteNaoEncontrada(livro.estanteId)
        }
        livrosGuardados[livro.id] = livro
    }

    func apagarLivro(id: UUID) async throws {
        try gravando()
        livrosGuardados[id] = nil
        fotos[id] = nil
    }

    func prateleiras(naEstante estanteId: UUID) async throws -> [String] {
        try lendo()
        await durantePrateleiras?()
        let etiquetas = livrosGuardados.values
            .filter { $0.estanteId == estanteId }
            .compactMap { $0.prateleira }
            .filter { !$0.isEmpty }
        return Set(etiquetas).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func fotoMiniatura(doLivro livroId: UUID) async throws -> Data? {
        leiturasDeFoto += 1
        try lendo()
        return fotos[livroId]
    }

    func salvarFotoMiniatura(_ foto: Data?, doLivro livroId: UUID) async throws {
        gravacoesDeFoto += 1
        try gravando()
        if falharAoGravarFoto { throw FalhaSimulada() }
        guard livrosGuardados[livroId] != nil else { throw ErroPersistencia.livroNaoEncontrado(livroId) }
        fotos[livroId] = foto
    }

    // MARK: Categorias

    func categorias() async throws -> [Categoria] {
        try lendo()
        return categoriasGuardadas.values.sorted { $0.nome < $1.nome }
    }

    func salvar(_ categoria: Categoria) async throws {
        try gravando()
        categoriasGuardadas[categoria.id] = categoria
    }

    func apagarCategoria(id: UUID) async throws {
        try gravando()
        categoriasGuardadas[id] = nil
        for livro in livrosGuardados.values where livro.categoriaIds.contains(id) {
            livrosGuardados[livro.id]?.categoriaIds.remove(id)
        }
    }

    func quantidadeDeLivrosPorCategoria() async throws -> [UUID: Int] {
        try lendo()
        return categoriasGuardadas.keys.reduce(into: [:]) { quantidades, id in
            quantidades[id] = livrosGuardados.values.filter { $0.categoriaIds.contains(id) }.count
        }
    }
}
