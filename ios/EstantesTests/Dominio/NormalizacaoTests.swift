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
}
