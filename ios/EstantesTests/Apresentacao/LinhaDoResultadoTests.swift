import XCTest
@testable import Estantes

final class LinhaDoResultadoTests: XCTestCase {
    private let conceito = ItemSumario(nivel: 2, numeracao: "§ 5.108", titulo: "Conceito", pagina: "12")

    // MARK: - Item do sumário (onde está o assunto)

    func testItemComTudoPreenchido() {
        XCTAssertEqual(LinhaDoResultado.item(conceito), "§ 5.108 Conceito, p. 12")
    }

    func testItemSemNumeracao() {
        let item = ItemSumario(nivel: 1, titulo: "Conceito", pagina: "12")
        XCTAssertEqual(LinhaDoResultado.item(item), "Conceito, p. 12")
    }

    func testItemSemPagina() {
        let item = ItemSumario(nivel: 2, numeracao: "§ 5.108", titulo: "Conceito")
        XCTAssertEqual(LinhaDoResultado.item(item), "§ 5.108 Conceito")
    }

    // Prefácios são numerados em romanos: a página aparece como está impressa.
    func testItemComPaginaEmRomanosComoImpressa() {
        let item = ItemSumario(nivel: 1, titulo: "Prefácio", pagina: "XII")
        XCTAssertEqual(LinhaDoResultado.item(item), "Prefácio, p. XII")
    }

    // O livro casou pelo título ou pelo autor: nenhum item do sumário tem os termos.
    func testSemItem() {
        XCTAssertNil(LinhaDoResultado.item(nil))
    }

    // MARK: - Lugar (onde está o livro)

    func testLugarComEstanteEPrateleira() {
        XCTAssertEqual(LinhaDoResultado.lugar(estante: "Escritório", prateleira: "2ª de cima"), "Escritório · 2ª de cima")
    }

    func testLugarSemPrateleiraOuSoComEspacos() {
        XCTAssertEqual(LinhaDoResultado.lugar(estante: "Escritório", prateleira: nil), "Escritório")
        XCTAssertEqual(LinhaDoResultado.lugar(estante: "Escritório", prateleira: "  "), "Escritório")
    }

    // A estante do livro não está na lista que a tela leu (apagada entre a busca e o desenho).
    func testLugarComEstanteDesconhecida() {
        XCTAssertEqual(LinhaDoResultado.lugar(estante: nil, prateleira: "2ª de cima"), "2ª de cima")
    }

    func testLugarSemNada() {
        XCTAssertNil(LinhaDoResultado.lugar(estante: nil, prateleira: " "))
    }

    // MARK: - Ausentes (OU de reserva)

    func testPalavrasAusentesNaOrdemRecebida() {
        XCTAssertEqual(LinhaDoResultado.ausentes(["stf"]), "sem: stf")
        XCTAssertEqual(LinhaDoResultado.ausentes(["stf", "cpc"]), "sem: stf, cpc")
        XCTAssertNil(LinhaDoResultado.ausentes([]))
    }
}
