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

    /// Ligados, fazem as leituras ou as gravações lançarem `FalhaSimulada`.
    var falharAoLer = false
    var falharAoGravar = false

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
        let etiquetas = livrosGuardados.values
            .filter { $0.estanteId == estanteId }
            .compactMap { $0.prateleira }
            .filter { !$0.isEmpty }
        return Set(etiquetas).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func fotoCapa(doLivro livroId: UUID) async throws -> Data? {
        try lendo()
        return fotos[livroId]
    }

    func salvarFotoCapa(_ foto: Data?, doLivro livroId: UUID) async throws {
        try gravando()
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
}
