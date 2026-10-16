import XCTest
@testable import Estantes

final class QuantidadeTests: XCTestCase {
    func testLivrosNoSingularENoPlural() {
        XCTAssertEqual(Quantidade.livros(0), "0 livros")
        XCTAssertEqual(Quantidade.livros(1), "1 livro")
        XCTAssertEqual(Quantidade.livros(12), "12 livros")
        XCTAssertEqual(Quantidade.livros(1, comArtigo: true), "o livro")
        XCTAssertEqual(Quantidade.livros(3, comArtigo: true), "os 3 livros")
    }
}
