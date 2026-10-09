import CoreData

// Conversão entre as classes do Core Data (`…MO`) e as structs do Domínio.
// É o ÚNICO lugar do app onde as duas se encontram.
//
// Quem escreveu (tarefa 2.2, parte [eu escrevo]): `CategoriaMO` e `ItemSumarioMO` pelo Ricardo;
// `EstanteMO` (exemplo) e `LivroMO` pelo Claude, a pedido dele.
// Testes: EstantesTests/Dados/BibliotecaRepositorioCoreDataTests.swift
//
// Divisão do trabalho:
// - `paraDominio()`: lê o objeto do Core Data e monta a struct.
// - `preencher(com:)`: copia os campos da struct para o objeto (inclusive o `id`).
//   Só ATRIBUTOS: as relações (estante, categorias, itens do sumário) e a `fotoCapa` são do repositório,
//   que precisa buscar outros objetos no contexto para ligá-los.
//
// Enums com valor desconhecido no banco (`?? .cinza`, `?? .manual`): de propósito, o app mostra um valor
// neutro em vez de travar ou de obrigar toda leitura a tratar erro. Só aconteceria com um caso renomeado
// ou um banco de versão mais nova; os testes de contrato dos `rawValue` (EntidadesTests) evitam o primeiro.

/// Como listas de texto viram uma String só no Core Data.
enum FormatoPersistido {
    /// Um autor por linha: os nomes já têm vírgula ("Sobrenome, Nome").
    static let separadorAutores = "\n"
    /// Decidido no PLANO.md: "Direito > Direito civil > Contratos".
    static let separadorCddir = " > "
}

// Exemplo escrito pelo Claude, para servir de modelo às outras três.
extension EstanteMO {
    /// Banco → Domínio: cria uma struct nova com os valores guardados NESTE objeto.
    /// Dentro da extensão, `id`, `nome` e `criadaEm` são as propriedades do próprio `EstanteMO`
    /// (o mesmo que `self.id`, `self.nome`, `self.criadaEm`).
    func paraDominio() -> Estante {
        Estante(id: id, nome: nome, criadaEm: criadaEm)
    }

    /// Domínio → banco: copia cada campo da struct para este objeto. Não devolve nada:
    /// o objeto já existe (o repositório o criou ou buscou) e só tem os atributos trocados.
    func preencher(com estante: Estante) {
        id = estante.id
        nome = estante.nome
        criadaEm = estante.criadaEm
    }
}

extension CategoriaMO {
    func paraDominio() -> Categoria {
        Categoria(id: id, nome: nome, cor: CorCategoria(rawValue: cor) ?? .cinza)
    }

    func preencher(com categoria: Categoria) {
        id = categoria.id
        nome = categoria.nome
        cor = categoria.cor.rawValue
    }
}

extension ItemSumarioMO {
    func paraDominio() -> ItemSumario {
        ItemSumario(
            id: id,
            nivel: Int(nivel),
            numeracao: numeracao,
            titulo: titulo,
            pagina: pagina,
            origem: OrigemItemSumario(rawValue: origem) ?? .manual
        )
    }

    /// - Parameter ordem: posição do item no array do livro.
    func preencher(com item: ItemSumario, ordem: Int) {
        id = item.id
        nivel = Int32(item.nivel)
        numeracao = item.numeracao
        titulo = item.titulo
        pagina = item.pagina
        origem = item.origem.rawValue
        self.ordem = Int32(ordem)
    }
}

// Escrito pelo Claude a pedido do Ricardo.
extension LivroMO {
    func paraDominio() -> Livro {
        Livro(
            id: id,
            // A relação `estante` é o objeto inteiro; o Domínio guarda só o id dele.
            estanteId: estante.id,
            titulo: titulo,
            subtitulo: subtitulo,
            autores: Self.lista(autores, separador: FormatoPersistido.separadorAutores),
            editora: editora,
            local: local,
            edicao: edicao,
            volume: volume?.intValue,
            volumeRotulo: volumeRotulo,
            parte: parte,
            serie: serie,
            artigosInicio: artigosInicio?.intValue,
            artigosFim: artigosFim?.intValue,
            ano: ano?.intValue,
            isbn13: isbn13,
            paginas: paginas?.intValue,
            cddir: cddir,
            cddirCaminho: Self.lista(cddirCaminho, separador: FormatoPersistido.separadorCddir),
            urn: urn,
            origem: OrigemLivro(rawValue: origem) ?? .manual,
            prateleira: prateleira,
            // Set<CategoriaMO> → [UUID] (o map devolve array) → Set<UUID>.
            categoriaIds: Set(categorias.map(\.id)),
            // O Set não tem ordem: ordena pela posição gravada e converte item a item.
            itensSumario: itensSumario
                .sorted { $0.ordem < $1.ordem }
                .map { $0.paraDominio() },
            adicionadoEm: adicionadoEm
        )
    }

    /// Só atributos. Estante, categorias, itens do sumário e foto da capa ficam com o repositório.
    func preencher(com livro: Livro) {
        id = livro.id
        titulo = livro.titulo
        subtitulo = livro.subtitulo
        autores = livro.autores.joined(separator: FormatoPersistido.separadorAutores)
        editora = livro.editora
        local = livro.local
        edicao = livro.edicao
        volume = livro.volume.map { NSNumber(value: $0) }
        volumeRotulo = livro.volumeRotulo
        parte = livro.parte
        serie = livro.serie
        artigosInicio = livro.artigosInicio.map { NSNumber(value: $0) }
        artigosFim = livro.artigosFim.map { NSNumber(value: $0) }
        ano = livro.ano.map { NSNumber(value: $0) }
        isbn13 = livro.isbn13
        paginas = livro.paginas.map { NSNumber(value: $0) }
        cddir = livro.cddir
        cddirCaminho = livro.cddirCaminho.joined(separator: FormatoPersistido.separadorCddir)
        urn = livro.urn
        origem = livro.origem.rawValue
        prateleira = livro.prateleira
        adicionadoEm = livro.adicionadoEm
    }

    /// Desfaz o `joined`. A armadilha: `"".components(separatedBy:)` devolve `[""]` (um item vazio),
    /// não `[]`. Sem este cuidado, um livro sem autores voltaria do banco com um autor "".
    private static func lista(_ texto: String, separador: String) -> [String] {
        texto.isEmpty ? [] : texto.components(separatedBy: separador)
    }
}
