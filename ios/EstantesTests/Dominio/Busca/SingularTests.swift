import XCTest
@testable import Estantes

final class SingularTests: XCTestCase {
    private func assertSingular(_ pares: [(String, String)], file: StaticString = #filePath, line: UInt = #line) {
        for (plural, singular) in pares {
            XCTAssertEqual(Singular.forma(plural), singular, plural, file: file, line: line)
        }
    }

    // MARK: - Uma regra por teste

    func testOesViraAo() {
        assertSingular([("prisoes", "prisao"), ("obrigacoes", "obrigacao"), ("sucessoes", "sucessao")])
    }

    func testAisViraAl() {
        assertSingular([("penais", "penal"), ("reais", "real"), ("tribunais", "tribunal")])
    }

    func testEisViraElSoComCincoLetrasOuMais() {
        assertSingular([("imoveis", "imovel"), ("papeis", "papel")])
        // Com quatro letras cai na regra geral: o singular de "leis" é "lei", não "lel".
        assertSingular([("leis", "lei"), ("reis", "rei")])
    }

    func testNsViraM() {
        assertSingular([("ordens", "ordem"), ("bens", "bem"), ("homens", "homem")])
    }

    func testResDepoisDeVogalTiraEs() {
        assertSingular([("cautelares", "cautelar"), ("credores", "credor"), ("mulheres", "mulher")])
        // Depois de consoante, o singular termina em "re": só sai o "s".
        assertSingular([("livres", "livre"), ("padres", "padre")])
    }

    func testZesTiraEs() {
        assertSingular([("juizes", "juiz"), ("vezes", "vez")])
    }

    func testVogalMaisSTiraOS() {
        assertSingular([("direitos", "direito"), ("partes", "parte"), ("garantias", "garantia"), ("atos", "ato")])
    }

    // MARK: - O que não muda

    func testSingularNaoMuda() {
        for termo in ["prisao", "cautelar", "direito", "processo", "civil", "lei", "penal", "lassale"] {
            XCTAssertEqual(Singular.forma(termo), termo, termo)
        }
    }

    func testExcecoes() {
        assertSingular([("arts", "art"), ("civis", "civil")])
        // A regra geral estragaria estas: "onus" viraria a ONU, "mais" viraria `mal`, "pais" (país) `pal`.
        for termo in ["onus", "mais", "demais", "jamais", "pais", "cais", "virus", "lapis", "bonus"] {
            XCTAssertEqual(Singular.forma(termo), termo, termo)
        }
    }

    func testTermosCurtosNumerosEMistosNaoMudam() {
        for termo in ["as", "os", "mes", "res", "1710", "8078", "cpc2015", "xlviii", "s"] {
            XCTAssertEqual(Singular.forma(termo), termo, termo)
        }
    }

    func testSingularDoSingularEhOMesmo() {
        // Aplicar duas vezes não pode mudar de novo: o índice guarda o termo e a consulta pode chegar
        // já no singular.
        for plural in ["prisoes", "penais", "imoveis", "ordens", "cautelares", "juizes", "direitos", "arts"] {
            let singular = Singular.forma(plural)
            XCTAssertEqual(Singular.forma(singular), singular, plural)
        }
    }
}
