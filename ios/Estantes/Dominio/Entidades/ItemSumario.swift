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
    /// Numeração impressa, separada do título ("Capítulo II", "1.2.3", "Art. 1.710", "§ 5.108").
    var numeracao: String?
    var titulo: String
    /// A página como está impressa ("245", "XI"). Texto porque prefácios usam romanos.
    /// Opcional: divisões como "Parte I" muitas vezes não têm página.
    var pagina: String?
    var origem: OrigemItemSumario

    init(
        id: UUID = UUID(),
        nivel: Int,
        numeracao: String? = nil,
        titulo: String,
        pagina: String? = nil,
        origem: OrigemItemSumario = .manual
    ) {
        self.id = id
        self.nivel = nivel
        self.numeracao = numeracao
        self.titulo = titulo
        self.pagina = pagina
        self.origem = origem
    }

    /// O número e a sequência (romana ou arábica) da página; `nil` sem página ou com texto que não é
    /// número ("s/n"). Derivado e não guardado: dois campos com a mesma informação poderiam divergir.
    var numeroDaPagina: NumeroDePagina? {
        pagina.flatMap(NumeroDePagina.interpretar)
    }
}
