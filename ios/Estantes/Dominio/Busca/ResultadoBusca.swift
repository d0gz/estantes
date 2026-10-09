import Foundation

/// Uma linha da lista de resultados. A prateleira vem no `livro`; o nome da estante não entra:
/// a tela resolve pelo `livro.estanteId`, e renomear uma estante não exige reindexar nada.
struct ResultadoBusca: Equatable {
    let livro: Livro
    /// O item do sumário que mais casa com a consulta (com a página), ou `nil`.
    let itemDoSumario: ItemSumario?
    /// Nota BM25F. Vale 0 na listagem só por filtro (consulta vazia), que não tem ranking.
    let nota: Double
}

/// O que a busca devolve: a lista e o que a tela precisa explicar sobre ela.
struct RespostaBusca: Equatable {
    let resultados: [ResultadoBusca]
    /// Palavras que não existiam na biblioteca e foram trocadas pelo termo mais próximo, para a tela
    /// avisar ("Mostrando resultados para *lassale*") e oferecer a busca sem correção.
    let correcoes: [Correcao]
}

/// Uma palavra da consulta trocada por um termo do vocabulário.
struct Correcao: Equatable {
    /// Como o usuário escreveu (normalizada: "lassalle").
    let digitado: String
    /// O termo usado no lugar (`lassale`).
    let usado: String
}
