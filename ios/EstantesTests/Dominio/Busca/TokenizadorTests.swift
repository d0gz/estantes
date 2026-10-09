import XCTest
@testable import Estantes

final class TokenizadorTests: XCTestCase {
    func testRemoveAcentosEMaiusculas() {
        XCTAssertEqual(Tokenizador.termos("AÇÃO Civil Pública"), ["acao", "civil", "publica"])
    }

    func testPontuacaoSepara() {
        XCTAssertEqual(Tokenizador.termos("Responsabilidade civil: teoria, prática."),
                       ["responsabilidade", "civil", "teoria", "pratica"])
    }

    func testOrdinalSaiDoNumero() {
        XCTAssertEqual(Tokenizador.termos("art. 5º"), ["art", "5"])
        XCTAssertEqual(Tokenizador.termos("3ª edição"), ["3", "edicao"])
    }

    func testHifenETravessaoSeparam() {
        XCTAssertEqual(Tokenizador.termos("Pós-graduação – Direito"), ["pos", "graduacao", "direito"])
    }

    func testPontoEntreDigitosNaoSepara() {
        XCTAssertEqual(Tokenizador.termos("Lei 8.078/90"), ["lei", "8078", "90"])
        XCTAssertEqual(Tokenizador.termos("Lei 8.078/90"), Tokenizador.termos("lei 8078/90"))
    }

    func testPontoNoFimDoNumeroSepara() {
        XCTAssertEqual(Tokenizador.termos("Lei 8.078. Comentários"), ["lei", "8078", "comentarios"])
    }

    func testRemovePalavrasVaziasInclusiveComAcento() {
        XCTAssertEqual(Tokenizador.termos("Código de Defesa do Consumidor"), ["codigo", "defesa", "consumidor"])
        XCTAssertEqual(Tokenizador.termos("Às vezes à prova"), ["vezes", "prova"])
    }

    func testMantemTermosJuridicosCurtos() {
        XCTAssertEqual(Tokenizador.termos("Lei, art. e CPC no STF"), ["lei", "art", "cpc", "stf"])
    }

    func testPreservaRepeticoes() {
        XCTAssertEqual(Tokenizador.termos("prisão e prisão preventiva"), ["prisao", "prisao", "preventiva"])
    }

    func testTextoSemTermosViraVazio() {
        XCTAssertEqual(Tokenizador.termos(""), [])
        XCTAssertEqual(Tokenizador.termos("  -- . "), [])
        XCTAssertEqual(Tokenizador.termos("de da do"), [])
    }
}
