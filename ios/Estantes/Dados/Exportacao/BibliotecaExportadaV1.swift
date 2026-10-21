import Foundation

/// O arquivo de exportação, versão 1: `{"versao": 1, "categorias": [...], "estantes": [{..., "livros": [...]}]}`.
///
/// Formato decidido em 21/10 (F1–F4) e congelado pelo `BibliotecaExportadaV1Tests`:
/// - chaves com o nome dos campos do Domínio; o livro fica dentro da estante (sem `estanteId`) e a ordem do
///   sumário é a do array;
/// - datas em ISO 8601 com milissegundos (o que passa disso se perde);
/// - opcional vazio sai sem chave; listas aparecem sempre e são obrigatórias na leitura;
/// - saída indentada, com chaves em ordem alfabética e `categoriaIds` ordenados: a mesma biblioteca dá sempre
///   o mesmo arquivo.
///
/// DTOs à parte, e não `Codable` nas entidades: o arquivo não muda quando uma struct do Domínio muda, e o
/// compilador obriga a decidir o que fazer com o v1. Cores e origens vão como texto e são convertidas à mão:
/// um valor desconhecido torna o arquivo inválido.
struct BibliotecaExportadaV1: CodificadorDeBiblioteca {
    static let versao = 1

    func codificar(_ conteudo: ConteudoDaBiblioteca) throws -> Data {
        let livrosPorEstante = Dictionary(grouping: conteudo.livros, by: \.estanteId)
        let arquivo = ArquivoDTO(
            versao: Self.versao,
            categorias: conteudo.categorias.map(CategoriaDTO.init),
            estantes: conteudo.estantes.map { estante in
                EstanteDTO(estante, livros: (livrosPorEstante[estante.id] ?? []).map(LivroDTO.init))
            }
        )
        let codificador = JSONEncoder()
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        codificador.dateEncodingStrategy = .custom { data, saida in
            var valor = saida.singleValueContainer()
            try valor.encode(Self.formatoDeData.string(from: data))
        }
        return try codificador.encode(arquivo)
    }

    func decodificar(_ dados: Data) throws -> ConteudoDaBiblioteca {
        let decodificador = JSONDecoder()
        decodificador.dateDecodingStrategy = .custom { entrada in
            let texto = try entrada.singleValueContainer().decode(String.self)
            guard let data = Self.formatoDeData.date(from: texto) else { throw ErroDeImportacao.arquivoInvalido }
            return data
        }
        // A versão primeiro: um arquivo mais novo pode ter outra estrutura inteira.
        guard let envelope = try? decodificador.decode(EnvelopeDTO.self, from: dados) else {
            throw ErroDeImportacao.arquivoInvalido
        }
        if envelope.versao > Self.versao { throw ErroDeImportacao.versaoMaisNova(envelope.versao) }
        guard envelope.versao == Self.versao,
              let arquivo = try? decodificador.decode(ArquivoDTO.self, from: dados) else {
            throw ErroDeImportacao.arquivoInvalido
        }
        return try arquivo.conteudo()
    }

    /// `ISO8601DateFormatter` é seguro entre threads; um só para todas as datas.
    private static let formatoDeData: ISO8601DateFormatter = {
        let formato = ISO8601DateFormatter()
        formato.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formato
    }()
}

// MARK: - DTOs (espelham o JSON; nomes = chaves)

private struct EnvelopeDTO: Decodable {
    let versao: Int
}

private struct ArquivoDTO: Codable {
    let versao: Int
    let categorias: [CategoriaDTO]
    let estantes: [EstanteDTO]

    func conteudo() throws -> ConteudoDaBiblioteca {
        ConteudoDaBiblioteca(
            estantes: estantes.map(\.estante),
            categorias: try categorias.map { try $0.categoria() },
            livros: try estantes.flatMap { estante in try estante.livros.map { try $0.livro(naEstante: estante.id) } }
        )
    }
}

private struct CategoriaDTO: Codable {
    let id: UUID
    let nome: String
    let cor: String

    init(_ categoria: Categoria) {
        id = categoria.id
        nome = categoria.nome
        cor = categoria.cor.rawValue
    }

    func categoria() throws -> Categoria {
        Categoria(id: id, nome: nome, cor: try valor(cor, de: CorCategoria.self))
    }
}

private struct EstanteDTO: Codable {
    let id: UUID
    let nome: String
    let criadaEm: Date
    let livros: [LivroDTO]

    init(_ estante: Estante, livros: [LivroDTO]) {
        id = estante.id
        nome = estante.nome
        criadaEm = estante.criadaEm
        self.livros = livros
    }

    var estante: Estante { Estante(id: id, nome: nome, criadaEm: criadaEm) }
}

private struct ColaboradorDTO: Codable {
    let nome: String
    let papel: String
}

private struct ItemSumarioDTO: Codable {
    let id: UUID
    let nivel: Int
    let numeracao: String?
    let titulo: String
    let pagina: String?
    let origem: String

    init(_ item: ItemSumario) {
        id = item.id
        nivel = item.nivel
        numeracao = item.numeracao
        titulo = item.titulo
        pagina = item.pagina
        origem = item.origem.rawValue
    }

    func item() throws -> ItemSumario {
        ItemSumario(id: id, nivel: nivel, numeracao: numeracao, titulo: titulo, pagina: pagina,
                    origem: try valor(origem, de: OrigemItemSumario.self))
    }
}

private struct LivroDTO: Codable {
    let id: UUID
    let titulo: String
    let subtitulo: String?
    let autores: [String]
    let colaboradores: [ColaboradorDTO]
    let editora: String?
    let local: String?
    let edicao: String?
    let volume: Int?
    let volumeRotulo: String?
    let parte: String?
    let serie: String?
    let artigosInicio: Int?
    let artigosFim: Int?
    let ano: Int?
    let isbn13: String?
    let paginas: Int?
    let cddir: String?
    let cddirCaminho: [String]
    let urn: String?
    let origem: String
    let prateleira: String?
    let categoriaIds: [UUID]
    let itensSumario: [ItemSumarioDTO]
    let adicionadoEm: Date

    init(_ livro: Livro) {
        id = livro.id
        titulo = livro.titulo
        subtitulo = livro.subtitulo
        autores = livro.autores
        colaboradores = livro.colaboradores.map { ColaboradorDTO(nome: $0.nome, papel: $0.papel) }
        editora = livro.editora
        local = livro.local
        edicao = livro.edicao
        volume = livro.volume
        volumeRotulo = livro.volumeRotulo
        parte = livro.parte
        serie = livro.serie
        artigosInicio = livro.artigosInicio
        artigosFim = livro.artigosFim
        ano = livro.ano
        isbn13 = livro.isbn13
        paginas = livro.paginas
        cddir = livro.cddir
        cddirCaminho = livro.cddirCaminho
        urn = livro.urn
        origem = livro.origem.rawValue
        prateleira = livro.prateleira
        categoriaIds = livro.categoriaIds.sorted { $0.uuidString < $1.uuidString }
        itensSumario = livro.itensSumario.map(ItemSumarioDTO.init)
        adicionadoEm = livro.adicionadoEm
    }

    func livro(naEstante estanteId: UUID) throws -> Livro {
        Livro(
            id: id, estanteId: estanteId, titulo: titulo, subtitulo: subtitulo, autores: autores,
            colaboradores: colaboradores.map { Colaborador(nome: $0.nome, papel: $0.papel) },
            editora: editora, local: local, edicao: edicao, volume: volume, volumeRotulo: volumeRotulo,
            parte: parte, serie: serie, artigosInicio: artigosInicio, artigosFim: artigosFim, ano: ano,
            isbn13: isbn13, paginas: paginas, cddir: cddir, cddirCaminho: cddirCaminho, urn: urn,
            origem: try valor(origem, de: OrigemLivro.self), prateleira: prateleira,
            categoriaIds: Set(categoriaIds), itensSumario: try itensSumario.map { try $0.item() },
            adicionadoEm: adicionadoEm
        )
    }
}

/// Texto do arquivo → enum do Domínio; valor desconhecido torna o arquivo inválido.
private func valor<T: RawRepresentable>(_ texto: String, de tipo: T.Type) throws -> T where T.RawValue == String {
    guard let valor = T(rawValue: texto) else { throw ErroDeImportacao.arquivoInvalido }
    return valor
}
