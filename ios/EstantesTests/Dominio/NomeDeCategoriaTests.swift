import XCTest
@testable import Estantes

final class NomeDeCategoriaTests: XCTestCase {
    private let tributario = Categoria(nome: "Direito Tributário", cor: .azul)
    private let penal = Categoria(nome: "Penal", cor: .vermelho)

    func testNomeNovoEhValido() {
        XCTAssertNil(NomeDeCategoria.validar("Consumidor", existentes: [tributario, penal]))
    }

    func testNomeVazioOuSoEspacosEhInvalido() {
        XCTAssertEqual(NomeDeCategoria.validar("", existentes: []), .vazio)
        XCTAssertEqual(NomeDeCategoria.validar("   ", existentes: []), .vazio)
    }

    func testRepetidoSemDiferenciarMaiusculasNemAcentos() {
        XCTAssertEqual(
            NomeDeCategoria.validar("direito  TRIBUTARIO", existentes: [tributario, penal]),
            .repetido(tributario)
        )
    }

    func testRenomearMantendoOProprioNomeEhValido() {
        XCTAssertNil(NomeDeCategoria.validar("Direito tributário", existentes: [tributario, penal], ignorando: tributario.id))
    }

    func testRenomearParaONomeDeOutraEhInvalido() {
        XCTAssertEqual(
            NomeDeCategoria.validar("penal", existentes: [tributario, penal], ignorando: tributario.id),
            .repetido(penal)
        )
    }
}
