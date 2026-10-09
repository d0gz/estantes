import XCTest
@testable import Estantes

/// Os valores brutos dos enums vão para o Core Data e para o JSON exportado:
/// estes testes travam os valores para que uma renomeação não quebre arquivos antigos.
final class EntidadesTests: XCTestCase {
    func testValoresBrutosDasOrigens() {
        XCTAssertEqual(OrigemLivro.allCases.map(\.rawValue), ["lexml", "googlebooks", "gemini", "manual"])
        XCTAssertEqual(OrigemItemSumario.allCases.map(\.rawValue), ["foto", "lexml", "gemini", "manual"])
    }

    func testPaletaTemDezCoresComValoresBrutosUnicos() {
        let valores = CorCategoria.allCases.map(\.rawValue)
        XCTAssertEqual(valores.count, 10)
        XCTAssertEqual(Set(valores).count, valores.count)
    }

    func testLivroNovoComecaManualSemSumarioNemCategorias() {
        let livro = Livro(estanteId: UUID(), titulo: "Curso de Direito Civil")
        XCTAssertEqual(livro.origem, .manual)
        XCTAssertTrue(livro.itensSumario.isEmpty)
        XCTAssertTrue(livro.categoriaIds.isEmpty)
    }

    func testLivroNovoNaoEhTomoDeObraEmVariosVolumes() {
        let livro = Livro(estanteId: UUID(), titulo: "Manual de direito penal")
        XCTAssertNil(livro.volume)
        XCTAssertNil(livro.volumeRotulo)
        XCTAssertNil(livro.parte)
        XCTAssertNil(livro.serie)
        XCTAssertNil(livro.artigosInicio)
        XCTAssertNil(livro.artigosFim)
        XCTAssertNil(livro.local)
    }

    func testStructsSaoValores() {
        var original = Livro(estanteId: UUID(), titulo: "Original")
        let copia = original
        original.titulo = "Alterado"
        XCTAssertEqual(copia.titulo, "Original")
    }
}
