import XCTest
@testable import Estantes

/// Os valores brutos dos enums vão para o Core Data e para o JSON exportado:
/// estes testes travam os valores para que uma renomeação não quebre arquivos antigos.
final class EntidadesTests: XCTestCase {
    func testValoresBrutosDasOrigens() {
        XCTAssertEqual(OrigemLivro.allCases.map(\.rawValue), ["lexml", "googlebooks", "gemini", "manual"])
        XCTAssertEqual(OrigemItemSumario.allCases.map(\.rawValue), ["foto", "lexml", "gemini", "manual"])
    }

    /// A ordem também é contrato: é o desempate da cor sugerida ao criar uma categoria.
    /// Lista de 16/10 (PLANO, Histórico): sem azul nem turquesa, que se confundiam com o destaque.
    func testValoresBrutosEOrdemDasCoresDeCategoria() {
        XCTAssertEqual(
            CorCategoria.allCases.map(\.rawValue),
            ["vermelho", "laranja", "amarelo", "verde", "menta", "indigo", "roxo", "rosa", "marrom", "cinza"]
        )
    }

    /// Mantém a ordem da lista (não a do conjunto de ids) e ignora id sem categoria.
    func testCategoriasComIdsMantemAOrdemDaLista() {
        let civil = Categoria(nome: "Civil", cor: .laranja)
        let penal = Categoria(nome: "Penal", cor: .amarelo)
        let processo = Categoria(nome: "Processo", cor: .verde)

        let escolhidas = [civil, penal, processo].comIds([processo.id, civil.id, UUID()])

        XCTAssertEqual(escolhidas, [civil, processo])
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
