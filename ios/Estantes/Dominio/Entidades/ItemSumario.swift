import Foundation

/// De onde veio um item do sumário. Separado de `OrigemLivro` porque os valores possíveis são
/// outros: um item nunca vem do Google Books, e um livro nunca vem de uma foto do sumário.
enum OrigemItemSumario: String, CaseIterable {
    case foto
    case lexml
    case gemini
    case manual
}

/// Uma linha do sumário de um livro. Toda origem (foto, LexML, Gemini, escrita à mão) produz
/// este mesmo formato, e a `ValidacaoSumario` vale para todas.
struct ItemSumario: Identifiable, Equatable {
    let id: UUID
    /// 1 = seção de topo; 2 = subseção; e assim por diante.
    var nivel: Int
    /// Numeração impressa, separada do título ("Capítulo II", "1.2.3").
    var numeracao: String?
    var titulo: String
    /// Opcional: divisões como "Parte I" muitas vezes não têm página.
    var pagina: Int?
    var origem: OrigemItemSumario

    init(
        id: UUID = UUID(),
        nivel: Int,
        numeracao: String? = nil,
        titulo: String,
        pagina: Int? = nil,
        origem: OrigemItemSumario = .manual
    ) {
        self.id = id
        self.nivel = nivel
        self.numeracao = numeracao
        self.titulo = titulo
        self.pagina = pagina
        self.origem = origem
    }
}
