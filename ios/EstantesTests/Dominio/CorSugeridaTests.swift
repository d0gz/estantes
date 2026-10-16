import XCTest
@testable import Estantes

/// A cor que a folha de nova categoria já traz escolhida: a menos usada; no empate, a primeira na ordem da paleta
/// (`CorCategoria.allCases`, travada em `EntidadesTests`). Os esperados foram resolvidos à mão, contando os usos.
final class CorSugeridaTests: XCTestCase {
    func testSemCategoriasSugereAPrimeiraDaPaleta() {
        XCTAssertEqual(CorSugerida.sugerir(existentes: []), .vermelho)
    }

    /// vermelho 2, laranja 1, amarelo 1, o resto 0: sete cores empatam em 0 e a primeira delas na paleta é o verde
    /// (na ordem alfabética seria o "cinza"; na ordem das existentes, nenhuma delas aparece).
    func testEmpateNoMenorUsoFicaComAPrimeiraNaOrdemDaPaleta() {
        let existentes = [
            Categoria(nome: "Penal", cor: .amarelo),
            Categoria(nome: "Civil", cor: .laranja),
            Categoria(nome: "Processo", cor: .vermelho),
            Categoria(nome: "Trabalho", cor: .vermelho),
        ]
        XCTAssertEqual(CorSugerida.sugerir(existentes: existentes), .verde)
    }

    /// Todas usadas uma vez e o vermelho duas: o menor uso é 1, e a primeira com 1 é o laranja.
    func testComTodasAsCoresUsadasOMinimoDeixaDeSerZero() {
        let existentes = umaDeCada() + [Categoria(nome: "Extra", cor: .vermelho)]
        XCTAssertEqual(CorSugerida.sugerir(existentes: existentes), .laranja)
    }

    /// Todas usadas uma vez, e vermelho, laranja e amarelo duas: o menor uso (1) só aparece a partir do verde.
    /// Pega quem devolve a primeira da paleta sempre que todas as cores já estão presentes.
    func testOMenorUsoPodeEstarNoMeioDaPaleta() {
        let extras = [CorCategoria.vermelho, .laranja, .amarelo].map { Categoria(nome: "Extra \($0.rawValue)", cor: $0) }
        XCTAssertEqual(CorSugerida.sugerir(existentes: umaDeCada() + extras), .verde)
    }

    /// Uma categoria de cada cor, escrita à mão (e não com `allCases`) para o teste não depender do código.
    private func umaDeCada() -> [Categoria] {
        [
            Categoria(nome: "A", cor: .vermelho), Categoria(nome: "B", cor: .laranja),
            Categoria(nome: "C", cor: .amarelo), Categoria(nome: "D", cor: .verde),
            Categoria(nome: "E", cor: .menta), Categoria(nome: "F", cor: .indigo),
            Categoria(nome: "G", cor: .roxo), Categoria(nome: "H", cor: .rosa),
            Categoria(nome: "I", cor: .marrom), Categoria(nome: "J", cor: .cinza),
        ]
    }
}
