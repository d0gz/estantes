import XCTest
@testable import Estantes

final class NumeroDePaginaTests: XCTestCase {
    func testArabico() {
        XCTAssertEqual(NumeroDePagina.interpretar("1"), .arabico(1))
        XCTAssertEqual(NumeroDePagina.interpretar("245"), .arabico(245))
    }

    func testRomanosBasicosESubtrativos() {
        XCTAssertEqual(NumeroDePagina.interpretar("III"), .romano(3))
        XCTAssertEqual(NumeroDePagina.interpretar("IV"), .romano(4))
        XCTAssertEqual(NumeroDePagina.interpretar("IX"), .romano(9))
        XCTAssertEqual(NumeroDePagina.interpretar("XL"), .romano(40))
        XCTAssertEqual(NumeroDePagina.interpretar("XLVIII"), .romano(48))
        XCTAssertEqual(NumeroDePagina.interpretar("MCMLIV"), .romano(1954))
    }

    func testMinusculasEEspacosNasPontas() {
        XCTAssertEqual(NumeroDePagina.interpretar("xii"), .romano(12))
        XCTAssertEqual(NumeroDePagina.interpretar("  245 "), .arabico(245))
    }

    func testIntervaloValeOInicio() {
        XCTAssertEqual(NumeroDePagina.interpretar("XI-XII"), .romano(11))
        XCTAssertEqual(NumeroDePagina.interpretar("245-246"), .arabico(245))
        XCTAssertEqual(NumeroDePagina.interpretar("245 – 246"), .arabico(245))
    }

    func testTextoQueNaoEhPaginaDaNil() {
        for texto in ["", "   ", "s/n", "12a", "0", "-", "Art"] {
            XCTAssertNil(NumeroDePagina.interpretar(texto), texto)
        }
    }

    func testRomanoForaDaFormaCanonicaDaNil() {
        for texto in ["IIII", "IC", "VX", "IIIII", "XM", "VV"] {
            XCTAssertNil(NumeroDePagina.interpretar(texto), texto)
        }
    }

    func testInteiroParaRomano() {
        XCTAssertEqual(NumeroDePagina.romano(4), "IV")
        XCTAssertEqual(NumeroDePagina.romano(48), "XLVIII")
        XCTAssertEqual(NumeroDePagina.romano(1954), "MCMLIV")
        XCTAssertEqual(NumeroDePagina.romano(3999), "MMMCMXCIX")
        XCTAssertNil(NumeroDePagina.romano(0))
        XCTAssertNil(NumeroDePagina.romano(4000))
    }

    func testIdaEVoltaDeTodosOsNumeros() {
        for numero in 1...3999 {
            let texto = NumeroDePagina.romano(numero)!
            XCTAssertEqual(NumeroDePagina.inteiro(romano: texto), numero, texto)
        }
    }
}
