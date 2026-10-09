import Foundation

/// Os filtros da busca (as chips): autor, editora, faixa de anos, estantes, prefixo de CDDir e categorias.
///
/// Dimensões diferentes combinam com E; dentro de estantes e de categorias vale OU ("qualquer destas").
/// Opcional `nil`, texto em branco e conjunto vazio significam "sem filtro" naquela dimensão.
/// O motor aplica o filtro depois do BM25F, sobre os livros já pontuados: filtrar antes mudaria
/// o IDF e o mesmo livro mudaria de nota ao ligar uma chip.
struct FiltroBusca: Equatable {
    /// Cada palavra digitada precisa ser o começo de alguma palavra de um mesmo autor, em qualquer ordem:
    /// "jose afonso silva" e "silv" acham "Silva, José Afonso da". Usa o `Tokenizador` da busca, então
    /// palavras vazias ("da") são ignoradas.
    var autor: String?
    /// Basta a editora conter o texto, sem diferenciar maiúsculas nem acentos.
    var editora: String?
    /// Limites inclusivos. Com qualquer um deles, livro sem ano fica de fora; faixa invertida não aceita nenhum.
    var anoMinimo: Int?
    var anoMaximo: Int?
    var estanteIds: Set<UUID>
    /// "341.1" aceita "341.12": na classificação decimal, o prefixo é o assunto mais geral.
    var prefixoCDDir: String?
    var categoriaIds: Set<UUID>

    init(
        autor: String? = nil,
        editora: String? = nil,
        anoMinimo: Int? = nil,
        anoMaximo: Int? = nil,
        estanteIds: Set<UUID> = [],
        prefixoCDDir: String? = nil,
        categoriaIds: Set<UUID> = []
    ) {
        self.autor = autor
        self.editora = editora
        self.anoMinimo = anoMinimo
        self.anoMaximo = anoMaximo
        self.estanteIds = estanteIds
        self.prefixoCDDir = prefixoCDDir
        self.categoriaIds = categoriaIds
    }

    /// Nenhuma dimensão ligada: aceita qualquer livro.
    var estaVazio: Bool {
        FiltroBusca.termos(autor).isEmpty
            && FiltroBusca.textoNormalizado(editora) == nil
            && anoMinimo == nil
            && anoMaximo == nil
            && estanteIds.isEmpty
            && FiltroBusca.semEspacos(prefixoCDDir) == nil
            && categoriaIds.isEmpty
    }

    func aceita(_ livro: Livro) -> Bool {
        let termosDoAutor = FiltroBusca.termos(autor)
        if !termosDoAutor.isEmpty,
           !livro.autores.contains(where: { FiltroBusca.autor($0, casaCom: termosDoAutor) }) {
            return false
        }
        if let editoraProcurada = FiltroBusca.textoNormalizado(editora),
           !Normalizacao.chave(livro.editora ?? "").contains(editoraProcurada) {
            return false
        }
        if anoMinimo != nil || anoMaximo != nil {
            guard let ano = livro.ano else { return false }
            if let minimo = anoMinimo, ano < minimo { return false }
            if let maximo = anoMaximo, ano > maximo { return false }
        }
        if !estanteIds.isEmpty, !estanteIds.contains(livro.estanteId) {
            return false
        }
        if let prefixoProcurado = FiltroBusca.semEspacos(prefixoCDDir) {
            guard let cddir = FiltroBusca.semEspacos(livro.cddir), cddir.hasPrefix(prefixoProcurado) else {
                return false
            }
        }
        if !categoriaIds.isEmpty, categoriaIds.isDisjoint(with: livro.categoriaIds) {
            return false
        }
        return true
    }

    /// Todos os termos procurados no mesmo autor: "José Grinover" não casa com um livro que tenha
    /// um José e uma Grinover como coautores.
    private static func autor(_ nome: String, casaCom termosProcurados: [String]) -> Bool {
        let termosDoNome = Tokenizador.termos(nome)
        return termosProcurados.allSatisfy { procurado in
            termosDoNome.contains { $0.hasPrefix(procurado) }
        }
    }

    private static func termos(_ texto: String?) -> [String] {
        Tokenizador.termos(texto ?? "")
    }

    /// Texto normalizado, ou `nil` se estiver ausente ou em branco.
    private static func textoNormalizado(_ texto: String?) -> String? {
        guard let texto = texto else { return nil }
        let normalizado = Normalizacao.chave(texto)
        return normalizado.isEmpty ? nil : normalizado
    }

    /// Código sem nenhum espaço, nem nas pontas nem no meio ("341 .2" vira "341.2"),
    /// ou `nil` se estiver ausente ou em branco.
    private static func semEspacos(_ texto: String?) -> String? {
        guard let texto = texto else { return nil }
        let codigo = texto.filter { !$0.isWhitespace }
        return codigo.isEmpty ? nil : codigo
    }
}
