import Foundation

/// Os campos do livro que entram no índice. No BM25F cada um tem peso e `b` próprios.
/// Editora, ano, estante e CDDir (código) não estão aqui: são filtros, não texto pesquisado.
enum CampoBusca: CaseIterable {
    case titulo
    case subtitulo
    case autores
    case categorias
    case cddirCaminho
    case sumario
}

/// Os termos de um item do sumário, guardados para escolher o item mostrado no resultado
/// sem tokenizar de novo na hora da busca.
struct ItemSumarioIndexado: Equatable {
    let id: UUID
    /// Termo → quantas vezes aparece na numeração e no título do item.
    let frequencias: [String: Int]
    /// Total de termos do item (com repetições).
    let tamanho: Int
}

/// Índice invertido da biblioteca, em memória: do termo para os livros que o contêm.
///
/// Guarda o que o BM25F consome: a frequência do termo em cada campo de cada livro (`tf`), o tamanho
/// de cada campo, as somas para as médias e, pelo número de livros de cada termo, o `df` do IDF.
struct IndiceInvertido {
    /// O que o índice sabe de cada livro. Os `termos` existem para que `remover` visite só as
    /// entradas daquele livro, em vez de varrer o vocabulário inteiro.
    private struct Documento {
        let tamanhos: [CampoBusca: Int]
        let termos: Set<String>
        let itensSumario: [ItemSumarioIndexado]
    }

    /// Termo → livro → campo → frequência. Só aparecem os campos onde o termo ocorre.
    private var postings: [String: [UUID: [CampoBusca: Int]]] = [:]
    private var documentos: [UUID: Documento] = [:]
    /// Somas mantidas a cada inclusão e remoção: as médias saem sem recontar a biblioteca.
    private var somaDosTamanhos: [CampoBusca: Int] = [:]
    private var somaDosTamanhosDosItens = 0
    private var quantidadeDeItens = 0

    // MARK: - Alteração

    /// Indexa o livro. Se ele já estava no índice, a versão antiga sai antes: reindexar é chamar
    /// `adicionar` de novo. O livro só guarda os ids das categorias; os nomes vêm de fora, e ids
    /// sem nome no dicionário são ignorados. Os nomes ficam gravados como estavam na chamada:
    /// quem renomear ou apagar uma categoria precisa reindexar os livros dela.
    mutating func adicionar(_ livro: Livro, nomesDasCategorias: [UUID: String]) {
        remover(livro.id)

        // A numeração entra com o título do item: "art 1710" acha "Art. 1.710 — Do bem de família".
        // Números estruturais ("1.2.3" → `123`) viram um ruído pequeno, aceito (PLANO, 09/10).
        let termosDosItens = livro.itensSumario.map {
            Tokenizador.termos($0.numeracao ?? "") + Tokenizador.termos($0.titulo)
        }
        let termosPorCampo: [CampoBusca: [String]] = [
            .titulo: Tokenizador.termos(livro.titulo),
            // A parte de um tomo tem o papel do subtítulo (texto médio da folha de rosto): mesmo campo e peso.
            .subtitulo: Tokenizador.termos(livro.subtitulo ?? "") + Tokenizador.termos(livro.parte ?? ""),
            .autores: livro.autores.flatMap(Tokenizador.termos),
            .categorias: livro.categoriaIds.compactMap { nomesDasCategorias[$0] }.flatMap(Tokenizador.termos),
            .cddirCaminho: livro.cddirCaminho.flatMap(Tokenizador.termos),
            .sumario: termosDosItens.flatMap { $0 },
        ]

        var tamanhos: [CampoBusca: Int] = [:]
        var termosDoLivro: Set<String> = []
        for (campo, termos) in termosPorCampo {
            tamanhos[campo] = termos.count
            somaDosTamanhos[campo, default: 0] += termos.count
            for termo in termos {
                postings[termo, default: [:]][livro.id, default: [:]][campo, default: 0] += 1
                termosDoLivro.insert(termo)
            }
        }

        let itens = zip(livro.itensSumario, termosDosItens).map { item, termos in
            ItemSumarioIndexado(
                id: item.id,
                frequencias: termos.reduce(into: [:]) { $0[$1, default: 0] += 1 },
                tamanho: termos.count
            )
        }
        somaDosTamanhosDosItens += itens.reduce(0) { $0 + $1.tamanho }
        quantidadeDeItens += itens.count

        documentos[livro.id] = Documento(tamanhos: tamanhos, termos: termosDoLivro, itensSumario: itens)
    }

    /// Tira o livro do índice. Termos que só ele tinha somem do vocabulário. Id ausente é ignorado.
    mutating func remover(_ id: UUID) {
        guard let documento = documentos.removeValue(forKey: id) else { return }

        for termo in documento.termos {
            postings[termo]?[id] = nil
            if postings[termo]?.isEmpty == true {
                postings[termo] = nil
            }
        }
        for (campo, tamanho) in documento.tamanhos {
            somaDosTamanhos[campo, default: 0] -= tamanho
        }
        somaDosTamanhosDosItens -= documento.itensSumario.reduce(0) { $0 + $1.tamanho }
        quantidadeDeItens -= documento.itensSumario.count
    }

    // MARK: - Consulta (o que o BM25F usa)

    /// `N` do IDF.
    var totalDeLivros: Int { documentos.count }

    /// Os livros que contêm o termo, com a frequência em cada campo onde ele aparece.
    /// Campos onde o termo não aparece ficam de fora do dicionário: ausente vale 0 (use `?? 0`).
    func ocorrencias(de termo: String) -> [UUID: [CampoBusca: Int]] {
        postings[termo] ?? [:]
    }

    /// Os termos do vocabulário que começam com o prefixo (o próprio prefixo incluído, se existir),
    /// em ordem alfabética. Percorre o vocabulário inteiro: O(V), barato para uma biblioteca pessoal.
    func termos(comPrefixo prefixo: String) -> [String] {
        postings.keys.filter { $0.hasPrefix(prefixo) }.sorted()
    }

    /// `df` do IDF: em quantos livros o termo aparece, em qualquer campo.
    func quantidadeDeLivros(contendo termo: String) -> Int {
        postings[termo]?.count ?? 0
    }

    /// Quantos termos o campo tem naquele livro (0 se o campo está vazio ou o livro não existe).
    func tamanho(de campo: CampoBusca, noLivro id: UUID) -> Int {
        documentos[id]?.tamanhos[campo] ?? 0
    }

    /// Tamanho médio do campo sobre todos os livros, incluindo os que têm o campo vazio.
    func tamanhoMedio(de campo: CampoBusca) -> Double {
        guard totalDeLivros > 0 else { return 0 }
        return Double(somaDosTamanhos[campo] ?? 0) / Double(totalDeLivros)
    }

    /// Os itens do sumário do livro, na ordem do sumário.
    func itensSumario(doLivro id: UUID) -> [ItemSumarioIndexado] {
        documentos[id]?.itensSumario ?? []
    }

    /// Tamanho médio de um item do sumário, sobre todos os itens da biblioteca.
    var tamanhoMedioDosItens: Double {
        guard quantidadeDeItens > 0 else { return 0 }
        return Double(somaDosTamanhosDosItens) / Double(quantidadeDeItens)
    }
}
