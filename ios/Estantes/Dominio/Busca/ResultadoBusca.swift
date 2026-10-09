import Foundation

/// Uma linha da lista de resultados. A prateleira vem no `livro`; o nome da estante não entra:
/// a tela resolve pelo `livro.estanteId`, e renomear uma estante não exige reindexar nada.
struct ResultadoBusca: Equatable {
    let livro: Livro
    /// Nota BM25F. Vale 0 na listagem só por filtro (consulta vazia), que não tem ranking.
    let nota: Double
}
