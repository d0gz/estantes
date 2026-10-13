import XCTest
@testable import Estantes

/// Esperados dos exemplos da Wikipédia ("International Standard Book Number"): 978-0-306-40615-7 e o seu ISBN-10,
/// 0-306-40615-2; e 0-8044-2957-X (ISBN-10 com "X"). A conversão deste último para 13 foi feita à mão:
/// 978080442957 → pesos 1,3,1,3… somam 117 → dígito (10 − 7) = 3. Também à mão: 979100000000 soma 42 → 8, e o
/// EAN de produto 789123456789 soma 135 → 5.
final class ISBNTests: XCTestCase {
    func testISBN13ComHifensOuEspacosViraSoDigitos() {
        XCTAssertEqual(ISBN.normalizar("978-0-306-40615-7"), "9780306406157")
        XCTAssertEqual(ISBN.normalizar(" 978 0 306 40615 7 "), "9780306406157")
    }

    func testHifensUnicodeCopiadosDaWebTambemSeparam() {
        XCTAssertEqual(ISBN.normalizar("978\u{2010}0\u{2010}306\u{2010}40615\u{2010}7"), "9780306406157")
        XCTAssertEqual(ISBN.normalizar("978\u{2011}0\u{2011}306\u{2011}40615\u{2011}7"), "9780306406157")
        XCTAssertEqual(ISBN.normalizar("978\u{2013}0\u{2013}306\u{2013}40615\u{2013}7"), "9780306406157")
    }

    func testISBN13ComPrefixo979() {
        XCTAssertEqual(ISBN.normalizar("979-1-000000-00-8"), "9791000000008")
    }

    /// Todo ISBN-13 começa com 978 ou 979; o código de barras de um produto (789… é o Brasil) não é livro.
    func testEANDeProdutoComVerificadorCertoNaoEhISBN() {
        XCTAssertNil(ISBN.normalizar("7891234567895"))
    }

    func testDigitosForaDoASCIISaoInvalidos() {
        XCTAssertNil(ISBN.normalizar("978030640615\u{0667}"))
        XCTAssertNil(ISBN.normalizar("030640615\u{0662}"))
    }

    func testISBN10ViraOISBN13() {
        XCTAssertEqual(ISBN.normalizar("0-306-40615-2"), "9780306406157")
    }

    func testISBN10ComXNoFim() {
        XCTAssertEqual(ISBN.normalizar("0-8044-2957-X"), "9780804429573")
        XCTAssertEqual(ISBN.normalizar("0-8044-2957-x"), "9780804429573")
    }

    func testDigitoVerificadorErradoEInvalido() {
        XCTAssertNil(ISBN.normalizar("978-0-306-40615-8"))
        XCTAssertNil(ISBN.normalizar("0-306-40615-3"))
    }

    func testLetrasSaoInvalidas() {
        XCTAssertNil(ISBN.normalizar("978030640615A"))
        XCTAssertNil(ISBN.normalizar("ISBN 9780306406157"))
        // O "X" só vale como último caractere do ISBN-10.
        XCTAssertNil(ISBN.normalizar("08044X2957"))
        XCTAssertNil(ISBN.normalizar("978030640615X"))
    }

    func testComprimentoErradoEInvalido() {
        XCTAssertNil(ISBN.normalizar(""))
        XCTAssertNil(ISBN.normalizar("97803064061"))
        XCTAssertNil(ISBN.normalizar("97803064061577"))
    }
}
