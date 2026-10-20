import XCTest
@testable import Estantes

final class NormalizacaoTests: XCTestCase {
    func testRemoveAcentosEMaiusculas() {
        XCTAssertEqual(Normalizacao.chave("Direito Tributário"), "direito tributario")
        XCTAssertEqual(Normalizacao.chave("AÇÃO CIVIL PÚBLICA"), "acao civil publica")
    }

    func testReduzEspacosEAparaAsPontas() {
        XCTAssertEqual(Normalizacao.chave("  Processo   Civil \n"), "processo civil")
    }

    func testSoEspacosViraVazio() {
        XCTAssertEqual(Normalizacao.chave("   "), "")
    }

    func testTextoLimpoJuntaEspacosEQuebrasMasMantemMaiusculasEAcentos() {
        XCTAssertEqual(Normalizacao.textoLimpo("  Capítulo \n  II "), "Capítulo II")
    }

    func testTextoLimpoSoDeEspacosViraNil() {
        XCTAssertNil(Normalizacao.textoLimpo(" \n\t "))
    }
}
