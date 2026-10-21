import XCTest
@testable import Estantes

/// Casos decididos em 21/10: um arquivo incoerente é rejeitado inteiro.
final class ValidacaoDaBibliotecaTests: XCTestCase {
    private let idEscritorio = UUID(uuidString: "E0000000-0000-0000-0000-000000000001")!
    private let idKelsen = UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!
    private let idReale = UUID(uuidString: "B0000000-0000-0000-0000-000000000002")!

    private var escritorio: Estante { Estante(id: idEscritorio, nome: "Escritório") }

    func testConteudoCoerenteNaoTemProblema() {
        let conteudo = ConteudoDaBiblioteca(
            estantes: [escritorio],
            livros: [Livro(id: idKelsen, estanteId: idEscritorio, titulo: "Teoria pura do direito")]
        )
        XCTAssertNil(ValidacaoDaBiblioteca.validar(conteudo))
    }

    func testDoisLivrosComOMesmoUUIDSaoRejeitados() {
        let conteudo = ConteudoDaBiblioteca(
            estantes: [escritorio],
            livros: [
                Livro(id: idKelsen, estanteId: idEscritorio, titulo: "Teoria pura do direito"),
                Livro(id: idKelsen, estanteId: idEscritorio, titulo: "Lições preliminares de direito"),
            ]
        )
        XCTAssertEqual(ValidacaoDaBiblioteca.validar(conteudo), .idRepetido(idKelsen))
    }

    func testDuasEstantesComOMesmoUUIDSaoRejeitadas() {
        let conteudo = ConteudoDaBiblioteca(estantes: [escritorio, Estante(id: idEscritorio, nome: "Sala")])
        XCTAssertEqual(ValidacaoDaBiblioteca.validar(conteudo), .idRepetido(idEscritorio))
    }

    private let idCivil = UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!
    private let idSumida = UUID(uuidString: "C0000000-0000-0000-0000-000000000099")!

    func testLivroComCategoriaQueNaoEstaNoArquivoEhRejeitado() {
        let conteudo = ConteudoDaBiblioteca(
            estantes: [escritorio],
            categorias: [Categoria(id: idCivil, nome: "Civil", cor: .laranja)],
            livros: [Livro(id: idKelsen, estanteId: idEscritorio, titulo: "Teoria pura do direito",
                           categoriaIds: [idCivil, idSumida])]
        )
        XCTAssertEqual(ValidacaoDaBiblioteca.validar(conteudo), .categoriaInexistente(livro: idKelsen, categoria: idSumida))
    }

    func testDuasCategoriasComOMesmoNomeSemDiferenciarAcentosSaoRejeitadas() {
        let tributario = Categoria(nome: "Tributário", cor: .verde)
        let conteudo = ConteudoDaBiblioteca(categorias: [tributario, Categoria(nome: "tributario", cor: .roxo)])
        XCTAssertEqual(ValidacaoDaBiblioteca.validar(conteudo), .nomeDeCategoria(.repetido(tributario)))
    }

    func testCategoriaSemNomeEhRejeitada() {
        let conteudo = ConteudoDaBiblioteca(categorias: [Categoria(nome: "  ", cor: .cinza)])
        XCTAssertEqual(ValidacaoDaBiblioteca.validar(conteudo), .nomeDeCategoria(.vazio))
    }

    private func comUmLivro(isbn13: String? = nil, sumario: [ItemSumario] = []) -> ConteudoDaBiblioteca {
        ConteudoDaBiblioteca(
            estantes: [escritorio],
            livros: [Livro(id: idKelsen, estanteId: idEscritorio, titulo: "Teoria pura do direito",
                           isbn13: isbn13, itensSumario: sumario)]
        )
    }

    func testISBNNormalizadoEValidoPassa() {
        XCTAssertNil(ValidacaoDaBiblioteca.validar(comUmLivro(isbn13: "9780306406157")))
    }

    /// O app sempre grava os 13 dígitos sem hífens: um ISBN com hífens veio de fora do app (decisão de 21/10).
    func testISBNComHifensEhRejeitadoMesmoSendoValido() {
        XCTAssertEqual(ValidacaoDaBiblioteca.validar(comUmLivro(isbn13: "978-0-306-40615-7")), .isbnInvalido(livro: idKelsen))
    }

    func testISBNComDigitoVerificadorErradoEhRejeitado() {
        XCTAssertEqual(ValidacaoDaBiblioteca.validar(comUmLivro(isbn13: "9780306406158")), .isbnInvalido(livro: idKelsen))
    }

    func testSumarioComErroEhRejeitado() {
        let sumario = [ItemSumario(nivel: 2, titulo: "Direito e natureza", pagina: "1")]
        XCTAssertEqual(ValidacaoDaBiblioteca.validar(comUmLivro(sumario: sumario)), .sumarioInvalido(livro: idKelsen))
    }

    /// Aviso (página que volta) não impede salvar na tela, e também não impede importar.
    func testSumarioSoComAvisoPassa() {
        let sumario = [
            ItemSumario(nivel: 1, titulo: "Direito e moral", pagina: "67"),
            ItemSumario(nivel: 1, titulo: "Direito e natureza", pagina: "1"),
        ]
        XCTAssertNil(ValidacaoDaBiblioteca.validar(comUmLivro(sumario: sumario)))
    }
}
