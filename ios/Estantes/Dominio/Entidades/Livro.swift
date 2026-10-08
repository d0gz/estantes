import Foundation

/// De onde vieram os dados do livro. O valor bruto (`String`) é o que vai para o Core Data e para
/// o JSON exportado, por isso não pode mudar depois de publicado.
enum OrigemLivro: String, CaseIterable {
    case lexml
    case googlebooks
    case gemini
    case manual
}

/// Um livro da biblioteca do usuário.
///
/// É a raiz de um agregado: os `itensSumario` vivem e morrem com o livro e são salvos junto com ele.
/// Já as categorias têm vida própria, então o livro guarda só os ids delas.
/// A foto da capa fica fora da struct (é carregada à parte pelo repositório): o índice da busca
/// carrega todos os livros ao abrir o app, e as imagens pesariam na memória.
struct Livro: Identifiable, Equatable {
    let id: UUID
    var estanteId: UUID
    var titulo: String
    var subtitulo: String?
    var autores: [String]
    var editora: String?
    var edicao: String?
    var ano: Int?
    var isbn13: String?
    var paginas: Int?
    /// Código da Classificação Decimal de Direito (filtro por prefixo).
    var cddir: String?
    /// Níveis da hierarquia da CDDir, do mais geral ao mais específico (entram no índice da busca).
    var cddirCaminho: [String]
    var urn: String?
    var origem: OrigemLivro
    /// Etiqueta livre do usuário ("2ª de cima", "caixa azul").
    var prateleira: String?
    var categoriaIds: Set<UUID>
    /// A posição no array é a ordem do sumário.
    var itensSumario: [ItemSumario]
    let adicionadoEm: Date

    init(
        id: UUID = UUID(),
        estanteId: UUID,
        titulo: String,
        subtitulo: String? = nil,
        autores: [String] = [],
        editora: String? = nil,
        edicao: String? = nil,
        ano: Int? = nil,
        isbn13: String? = nil,
        paginas: Int? = nil,
        cddir: String? = nil,
        cddirCaminho: [String] = [],
        urn: String? = nil,
        origem: OrigemLivro = .manual,
        prateleira: String? = nil,
        categoriaIds: Set<UUID> = [],
        itensSumario: [ItemSumario] = [],
        adicionadoEm: Date = Date()
    ) {
        self.id = id
        self.estanteId = estanteId
        self.titulo = titulo
        self.subtitulo = subtitulo
        self.autores = autores
        self.editora = editora
        self.edicao = edicao
        self.ano = ano
        self.isbn13 = isbn13
        self.paginas = paginas
        self.cddir = cddir
        self.cddirCaminho = cddirCaminho
        self.urn = urn
        self.origem = origem
        self.prateleira = prateleira
        self.categoriaIds = categoriaIds
        self.itensSumario = itensSumario
        self.adicionadoEm = adicionadoEm
    }
}
