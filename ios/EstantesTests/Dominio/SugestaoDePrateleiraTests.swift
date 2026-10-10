import XCTest
@testable import Estantes

final class SugestaoDePrateleiraTests: XCTestCase {
    private func sugerir(_ texto: String, _ etiquetas: [String], limite: Int = 5) -> [String] {
        SugestaoDePrateleira.sugerir(para: texto, entre: etiquetas, limite: limite)
    }

    func testSemEtiquetasNaoHaSugestao() {
        XCTAssertEqual(sugerir("", []), [])
        XCTAssertEqual(sugerir("caixa", []), [])
    }

    func testSemTextoSugereTodasEmOrdemNatural() {
        XCTAssertEqual(
            sugerir("", ["caixa azul", "10ª de cima", "2ª de cima"]),
            ["2ª de cima", "10ª de cima", "caixa azul"]
        )
    }

    func testTextoSoDeEspacosContaComoVazio() {
        XCTAssertEqual(sugerir("   ", ["b", "a"]), ["a", "b"])
    }

    func testGrafiasDaMesmaEtiquetaViramUmaSo() {
        // A ordem natural põe a minúscula antes; os espaços da grafia sugerida saem arrumados.
        XCTAssertEqual(sugerir("", ["Caixa azul", " caixa  azul ", "caixa azul"]), ["caixa azul"])
        XCTAssertEqual(sugerir("", ["Caixa  azul "]), ["Caixa azul"])
    }

    func testEtiquetaSoDeEspacosNaoESugerida() {
        XCTAssertEqual(sugerir("", ["  ", "", "caixa"]), ["caixa"])
    }

    func testConsultaIgnoraMaiusculasEAcentos() {
        XCTAssertEqual(sugerir("CAIXA", ["caixa azul", "2ª de cima"]), ["caixa azul"])
        XCTAssertEqual(sugerir("armario", ["Armário da sala"]), ["Armário da sala"])
    }

    func testComecaPeloTextoVemAntesDeSoConter() {
        XCTAssertEqual(
            sugerir("2", ["caixa 2", "2ª de cima", "sem número"]),
            ["2ª de cima", "caixa 2"]
        )
    }

    func testAchaNoMeioDaEtiqueta() {
        XCTAssertEqual(sugerir("az", ["caixa azul", "2ª de cima"]), ["caixa azul"])
    }

    func testEtiquetaIgualAoDigitadoNaoAparece() {
        XCTAssertEqual(sugerir("Caixa Azul ", ["caixa azul", "caixa azul clara"]), ["caixa azul clara"])
    }

    func testRespeitaOLimite() {
        let etiquetas = (1...8).map { "\($0)ª de cima" }
        XCTAssertEqual(sugerir("", etiquetas, limite: 3), ["1ª de cima", "2ª de cima", "3ª de cima"])
        XCTAssertEqual(sugerir("", etiquetas).count, 5)
    }
}
