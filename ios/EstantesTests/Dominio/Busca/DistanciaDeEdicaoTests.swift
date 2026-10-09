import XCTest
@testable import Estantes

final class DistanciaDeEdicaoTests: XCTestCase {
    func testIguaisEVazias() {
        XCTAssertEqual(DistanciaDeEdicao.entre("penal", "penal"), 0)
        XCTAssertEqual(DistanciaDeEdicao.entre("", ""), 0)
        XCTAssertEqual(DistanciaDeEdicao.entre("", "abc"), 3)
        XCTAssertEqual(DistanciaDeEdicao.entre("abc", ""), 3)
    }

    func testUmaOperacaoDeCadaTipo() {
        XCTAssertEqual(DistanciaDeEdicao.entre("penal", "venal"), 1)       // troca
        XCTAssertEqual(DistanciaDeEdicao.entre("proceso", "processo"), 1)  // inserção
        XCTAssertEqual(DistanciaDeEdicao.entre("lassalle", "lassale"), 1)  // remoção
        XCTAssertEqual(DistanciaDeEdicao.entre("porcesso", "processo"), 1) // transposição (Levenshtein: 2)
    }

    func testExemploClassicoESimetria() {
        XCTAssertEqual(DistanciaDeEdicao.entre("kitten", "sitting"), 3)
        XCTAssertEqual(DistanciaDeEdicao.entre("sitting", "kitten"), 3)
    }

    func testRestritaNaoEditaDeNovoOTrechoTransposto() {
        // Na Damerau–Levenshtein completa seria 2 ("ca" → "ac" → "abc"); na restrita (OSA), 3.
        XCTAssertEqual(DistanciaDeEdicao.entre("ca", "abc"), 3)
    }

    func testLimite() {
        XCTAssertEqual(DistanciaDeEdicao.entre("penal", "venal", limite: 1), 1)
        XCTAssertEqual(DistanciaDeEdicao.entre("penal", "penal", limite: 0), 0)
        XCTAssertNil(DistanciaDeEdicao.entre("kitten", "sitting", limite: 2))
        // Tamanhos já diferem mais que o limite: nem calcula.
        XCTAssertNil(DistanciaDeEdicao.entre("abcdef", "ab", limite: 1))
        // Corte no meio da tabela: nenhuma letra em comum.
        XCTAssertNil(DistanciaDeEdicao.entre("abcde", "vwxyz", limite: 2))
        XCTAssertEqual(DistanciaDeEdicao.entre("abcde", "vwxyz", limite: 5), 5)
    }
}
