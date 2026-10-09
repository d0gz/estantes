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

    func testHifenEntreLetrasJuntaETravessaoSepara() {
        XCTAssertEqual(Tokenizador.termos("Pós-graduação – Direito"), ["posgraduacao", "direito"])
        XCTAssertEqual(Tokenizador.termos("Pós-graduação—Direito"), ["posgraduacao", "direito"])
    }

    // MARK: - Hífen (2.3b)

    func testHifenEntreLetrasEhRemovido() {
        XCTAssertEqual(Tokenizador.termos("Sub-rogação"), ["subrogacao"])
        XCTAssertEqual(Tokenizador.termos("Sub-rogação"), Tokenizador.termos("subrogação"))
    }

    func testHifenEntreDigitosSepara() {
        XCTAssertEqual(Tokenizador.termos("Arts. 1.710-1.779"), ["arts", "1710", "1779"])
    }

    func testHifenEntreLetraEDigitoSepara() {
        XCTAssertEqual(Tokenizador.termos("CPC-2015"), ["cpc", "2015"])
        XCTAssertEqual(Tokenizador.termos("2015-CPC"), ["2015", "cpc"])
    }

    func testHifenNasPontasOuEntreEspacosSepara() {
        XCTAssertEqual(Tokenizador.termos("-sub rogação-"), ["sub", "rogacao"])
        XCTAssertEqual(Tokenizador.termos("sub - rogação"), ["sub", "rogacao"])
    }

    func testHifensUnicodeValemComoHifenComum() {
        XCTAssertEqual(Tokenizador.termos("sub\u{2010}rogação"), ["subrogacao"])
        XCTAssertEqual(Tokenizador.termos("sub\u{2011}rogação"), ["subrogacao"])
    }

    func testHifenInvisivelSome() {
        XCTAssertEqual(Tokenizador.termos("sub\u{00AD}rogação"), ["subrogacao"])
        XCTAssertEqual(Tokenizador.termos("1\u{00AD}710"), ["1710"])
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
