import XCTest
@testable import Estantes

final class FiltroBuscaTests: XCTestCase {
    private let estante1 = UUID()
    private let estante2 = UUID()
    private let penal = UUID()
    private let processo = UUID()
    private let civil = UUID()

    private lazy var livroCompleto = Livro(
        estanteId: estante1,
        titulo: "Curso de Direito Constitucional Positivo",
        autores: ["Silva, José Afonso da"],
        editora: "Malheiros Editores",
        ano: 2014,
        cddir: "341.2",
        categoriaIds: [penal, processo]
    )
    private lazy var livroSemDados = Livro(estanteId: estante2, titulo: "Anotações soltas")

    func testFiltroVazioAceitaTudo() {
        let filtro = FiltroBusca()

        XCTAssertTrue(filtro.estaVazio)
        XCTAssertTrue(filtro.aceita(livroCompleto))
        XCTAssertTrue(filtro.aceita(livroSemDados))
    }

    func testTextoEmBrancoContaComoSemFiltro() {
        let filtro = FiltroBusca(autor: "   ", editora: "", prefixoCDDir: " ")

        XCTAssertTrue(filtro.estaVazio)
        XCTAssertTrue(filtro.aceita(livroSemDados))
    }

    /// Um filtro por dimensão, cada um recusando o `livroCompleto`. Serve para dois testes.
    private lazy var umFiltroPorDimensao: [String: FiltroBusca] = [
        "autor": FiltroBusca(autor: "moraes"),
        "editora": FiltroBusca(editora: "saraiva"),
        "anoMinimo": FiltroBusca(anoMinimo: 2015),
        "anoMaximo": FiltroBusca(anoMaximo: 2013),
        "estanteIds": FiltroBusca(estanteIds: [estante2]),
        "prefixoCDDir": FiltroBusca(prefixoCDDir: "342"),
        "categoriaIds": FiltroBusca(categoriaIds: [civil]),
    ]

    /// `estaVazio` e `aceita` repetem a regra "em branco = sem filtro": se uma dimensão nova entrar
    /// num e não no outro, o motor pularia um filtro ligado (ou aplicaria um desligado).
    func testCadaDimensaoLigadaDeixaDeEstarVazioERecusaLivro() {
        XCTAssertEqual(umFiltroPorDimensao.count, 7)
        for (dimensao, filtro) in umFiltroPorDimensao {
            XCTAssertFalse(filtro.estaVazio, dimensao)
            XCTAssertFalse(filtro.aceita(livroCompleto), dimensao)
        }
    }

    // MARK: - Autor e editora

    func testAutorContemSemAcentoNemMaiusculas() {
        XCTAssertTrue(FiltroBusca(autor: "silva").aceita(livroCompleto))
        XCTAssertTrue(FiltroBusca(autor: "JOSE AFONSO").aceita(livroCompleto))
        XCTAssertFalse(FiltroBusca(autor: "moraes").aceita(livroCompleto))
    }

    func testAutorEmQualquerOrdemEPeloComecoDaPalavra() {
        XCTAssertTrue(FiltroBusca(autor: "José Afonso Silva").aceita(livroCompleto))
        XCTAssertTrue(FiltroBusca(autor: "silv").aceita(livroCompleto))
        XCTAssertTrue(FiltroBusca(autor: "af silva").aceita(livroCompleto))
        // "ilva" está no meio da palavra, não no começo.
        XCTAssertFalse(FiltroBusca(autor: "ilva").aceita(livroCompleto))
    }

    func testAutorSoComPalavraVaziaContaComoSemFiltro() {
        let filtro = FiltroBusca(autor: "da")

        XCTAssertTrue(filtro.estaVazio)
        XCTAssertTrue(filtro.aceita(livroSemDados))
    }

    func testAutorTodasAsPalavrasNoMesmoAutor() {
        let livro = Livro(estanteId: estante1, titulo: "Teoria geral", autores: ["Cintra, Antônio", "Grinover, Ada"])

        XCTAssertTrue(FiltroBusca(autor: "ada grinover").aceita(livro))
        XCTAssertFalse(FiltroBusca(autor: "antonio grinover").aceita(livro))
    }

    func testAutorBastaUmDosAutores() {
        let livro = Livro(estanteId: estante1, titulo: "Teoria geral", autores: ["Cintra, Antônio", "Grinover, Ada"])

        XCTAssertTrue(FiltroBusca(autor: "grinover").aceita(livro))
    }

    func testAutorExcluiLivroSemAutor() {
        XCTAssertFalse(FiltroBusca(autor: "silva").aceita(livroSemDados))
    }

    func testEditoraContemSemAcentoNemMaiusculas() {
        XCTAssertTrue(FiltroBusca(editora: "malheiros").aceita(livroCompleto))
        XCTAssertFalse(FiltroBusca(editora: "saraiva").aceita(livroCompleto))
        XCTAssertFalse(FiltroBusca(editora: "malheiros").aceita(livroSemDados))
    }

    // MARK: - Ano

    func testAnoSoMinimo() {
        XCTAssertTrue(FiltroBusca(anoMinimo: 2010).aceita(livroCompleto))
        XCTAssertFalse(FiltroBusca(anoMinimo: 2015).aceita(livroCompleto))
    }

    func testAnoSoMaximo() {
        XCTAssertTrue(FiltroBusca(anoMaximo: 2020).aceita(livroCompleto))
        XCTAssertFalse(FiltroBusca(anoMaximo: 2013).aceita(livroCompleto))
    }

    func testAnoLimitesInclusivos() {
        XCTAssertTrue(FiltroBusca(anoMinimo: 2014, anoMaximo: 2014).aceita(livroCompleto))
    }

    func testAnoExcluiLivroSemAno() {
        XCTAssertFalse(FiltroBusca(anoMinimo: 1900).aceita(livroSemDados))
        XCTAssertFalse(FiltroBusca(anoMaximo: 3000).aceita(livroSemDados))
    }

    func testFaixaInvertidaNaoAceitaNenhum() {
        // 2014 está entre os dois números, mas nenhum ano é ≥ 2020 e ≤ 2010 ao mesmo tempo.
        XCTAssertFalse(FiltroBusca(anoMinimo: 2020, anoMaximo: 2010).aceita(livroCompleto))
    }

    // MARK: - Estante, CDDir e categorias

    func testEstanteOuEntreAsEscolhidas() {
        XCTAssertTrue(FiltroBusca(estanteIds: [estante1]).aceita(livroCompleto))
        XCTAssertFalse(FiltroBusca(estanteIds: [estante2]).aceita(livroCompleto))
        XCTAssertTrue(FiltroBusca(estanteIds: [estante1, estante2]).aceita(livroCompleto))
    }

    func testCDDirPorPrefixo() {
        XCTAssertTrue(FiltroBusca(prefixoCDDir: "341").aceita(livroCompleto))
        XCTAssertTrue(FiltroBusca(prefixoCDDir: " 341.2 ").aceita(livroCompleto))
        // Espaço no meio também sai: código CDDir não tem espaço com significado.
        XCTAssertTrue(FiltroBusca(prefixoCDDir: "341 .2").aceita(livroCompleto))
        XCTAssertFalse(FiltroBusca(prefixoCDDir: "341.3").aceita(livroCompleto))
        XCTAssertFalse(FiltroBusca(prefixoCDDir: "341.21").aceita(livroCompleto))
    }

    func testCDDirExcluiLivroSemCodigo() {
        XCTAssertFalse(FiltroBusca(prefixoCDDir: "341").aceita(livroSemDados))
    }

    func testCategoriaOuEntreAsEscolhidas() {
        XCTAssertTrue(FiltroBusca(categoriaIds: [penal]).aceita(livroCompleto))
        XCTAssertTrue(FiltroBusca(categoriaIds: [civil, processo]).aceita(livroCompleto))
        XCTAssertFalse(FiltroBusca(categoriaIds: [civil]).aceita(livroCompleto))
        XCTAssertFalse(FiltroBusca(categoriaIds: [penal]).aceita(livroSemDados))
    }

    // MARK: - Combinação

    func testDimensoesCombinamComE() {
        let passaEmTudo = FiltroBusca(
            autor: "silva",
            editora: "malheiros",
            anoMinimo: 2000,
            anoMaximo: 2020,
            estanteIds: [estante1],
            prefixoCDDir: "341",
            categoriaIds: [penal]
        )
        XCTAssertTrue(passaEmTudo.aceita(livroCompleto))

        // Basta uma dimensão falhar, qualquer que seja, para o livro sair.
        let falhas: [String: (inout FiltroBusca) -> Void] = [
            "autor": { $0.autor = "moraes" },
            "editora": { $0.editora = "saraiva" },
            "anoMinimo": { $0.anoMinimo = 2015 },
            "anoMaximo": { $0.anoMaximo = 2013 },
            "estanteIds": { $0.estanteIds = [self.estante2] },
            "prefixoCDDir": { $0.prefixoCDDir = "342" },
            "categoriaIds": { $0.categoriaIds = [self.civil] },
        ]
        for (dimensao, falhar) in falhas {
            var filtro = passaEmTudo
            falhar(&filtro)
            XCTAssertFalse(filtro.aceita(livroCompleto), dimensao)
        }
    }
}
