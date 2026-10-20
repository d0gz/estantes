import XCTest
@testable import Estantes

final class LinhaDoResultadoTests: XCTestCase {
    private let conceito = ItemSumario(nivel: 2, numeracao: "§ 5.108", titulo: "Conceito", pagina: "12")

    // MARK: - Local (item, estante, prateleira)

    func testComTudoPreenchido() {
        XCTAssertEqual(
            LinhaDoResultado.local(item: conceito, estante: "Escritório", prateleira: "2ª de cima"),
            "§ 5.108 Conceito, p. 12 · Escritório · 2ª de cima"
        )
    }

    func testSemNumeracao() {
        let item = ItemSumario(nivel: 1, titulo: "Conceito", pagina: "12")
        XCTAssertEqual(
            LinhaDoResultado.local(item: item, estante: "Escritório", prateleira: "2ª de cima"),
            "Conceito, p. 12 · Escritório · 2ª de cima"
        )
    }

    func testSemPagina() {
        let item = ItemSumario(nivel: 2, numeracao: "§ 5.108", titulo: "Conceito")
        XCTAssertEqual(
            LinhaDoResultado.local(item: item, estante: "Escritório", prateleira: "2ª de cima"),
            "§ 5.108 Conceito · Escritório · 2ª de cima"
        )
    }

    // Prefácios são numerados em romanos: a página aparece como está impressa.
    func testPaginaEmRomanosComoImpressa() {
        let item = ItemSumario(nivel: 1, titulo: "Prefácio", pagina: "XII")
        XCTAssertEqual(
            LinhaDoResultado.local(item: item, estante: "Escritório", prateleira: "2ª de cima"),
            "Prefácio, p. XII · Escritório · 2ª de cima"
        )
    }

    // O livro casou pelo título ou pelo autor: nenhum item do sumário tem os termos.
    func testSemItem() {
        XCTAssertEqual(
            LinhaDoResultado.local(item: nil, estante: "Escritório", prateleira: "2ª de cima"),
            "Escritório · 2ª de cima"
        )
    }

    func testSemPrateleiraOuSoComEspacos() {
        XCTAssertEqual(
            LinhaDoResultado.local(item: conceito, estante: "Escritório", prateleira: nil),
            "§ 5.108 Conceito, p. 12 · Escritório"
        )
        XCTAssertEqual(
            LinhaDoResultado.local(item: conceito, estante: "Escritório", prateleira: "  "),
            "§ 5.108 Conceito, p. 12 · Escritório"
        )
    }

    // A estante do livro não está na lista que a tela leu (apagada entre a busca e o desenho).
    func testEstanteDesconhecida() {
        XCTAssertEqual(
            LinhaDoResultado.local(item: conceito, estante: nil, prateleira: "2ª de cima"),
            "§ 5.108 Conceito, p. 12 · 2ª de cima"
        )
    }

    // MARK: - Ausentes (OU de reserva)

    func testPalavrasAusentesNaOrdemRecebida() {
        XCTAssertEqual(LinhaDoResultado.ausentes(["stf"]), "sem: stf")
        XCTAssertEqual(LinhaDoResultado.ausentes(["stf", "cpc"]), "sem: stf, cpc")
        XCTAssertNil(LinhaDoResultado.ausentes([]))
    }
}
