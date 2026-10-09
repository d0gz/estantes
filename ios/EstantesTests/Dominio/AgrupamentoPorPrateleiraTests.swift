import XCTest
@testable import Estantes

final class AgrupamentoPorPrateleiraTests: XCTestCase {
    private let estanteId = UUID()

    private func livro(_ titulo: String, prateleira: String? = nil, volume: Int? = nil, ano: Int? = nil) -> Livro {
        Livro(estanteId: estanteId, titulo: titulo, volume: volume, ano: ano, prateleira: prateleira)
    }

    private func titulos(_ grupos: [GrupoDePrateleira]) -> [[String]] {
        grupos.map { $0.livros.map(\.titulo) }
    }

    func testSemLivrosNaoHaGrupos() {
        XCTAssertEqual(AgrupamentoPorPrateleira.agrupar([]), [])
    }

    func testGruposEmOrdemNaturalESemPrateleiraNoFim() {
        let grupos = AgrupamentoPorPrateleira.agrupar([
            livro("A", prateleira: "10ª de cima"),
            livro("B"),
            livro("C", prateleira: "2ª de cima"),
            livro("D", prateleira: "caixa azul"),
        ])

        XCTAssertEqual(grupos.map(\.prateleira), ["2ª de cima", "10ª de cima", "caixa azul", nil])
    }

    func testEtiquetaSoDeEspacosContaComoSemPrateleira() {
        let grupos = AgrupamentoPorPrateleira.agrupar([livro("A", prateleira: "   "), livro("B", prateleira: "")])

        XCTAssertEqual(grupos.map(\.prateleira), [nil])
        XCTAssertEqual(titulos(grupos), [["A", "B"]])
    }

    func testEtiquetasQueSoDiferemEmCaixaAcentoEEspacoSaoAMesma() {
        let grupos = AgrupamentoPorPrateleira.agrupar([
            livro("A", prateleira: "Caixa azul"),
            livro("B", prateleira: "caixa  azul "),
            livro("C", prateleira: "caixa azul"),
            livro("D", prateleira: "Cáixa Azul"),
        ])

        XCTAssertEqual(grupos.count, 1)
        // Quatro grafias, uma vez cada: empate, vence a primeira na ordem dos caracteres ("C" < "c", "a" < "á").
        XCTAssertEqual(grupos.first?.prateleira, "Caixa azul")
        XCTAssertEqual(titulos(grupos), [["A", "B", "C", "D"]])
    }

    func testGrafiaMostradaEAMaisUsada() {
        let grupos = AgrupamentoPorPrateleira.agrupar([
            livro("A", prateleira: "Caixa azul"),
            livro("B", prateleira: "caixa azul "),
            livro("C", prateleira: "caixa azul"),
        ])

        XCTAssertEqual(grupos.map(\.prateleira), ["caixa azul"])
    }

    func testNoEmpateDeGrafiaVenceAPrimeiraEmOrdemAlfabetica() {
        let grupos = AgrupamentoPorPrateleira.agrupar([
            livro("A", prateleira: "caixa azul"),
            livro("B", prateleira: "Caixa azul"),
        ])

        XCTAssertEqual(grupos.map(\.prateleira), ["Caixa azul"])
    }

    func testDentroDoGrupoOrdenaPorTituloSemAcentoNemCaixa() {
        let grupos = AgrupamentoPorPrateleira.agrupar([
            livro("Teoria pura do direito"),
            livro("ética e direito"),
            livro("Direito civil"),
            livro("Éxito processual"),
        ])

        XCTAssertEqual(titulos(grupos), [["Direito civil", "ética e direito", "Éxito processual", "Teoria pura do direito"]])
    }

    func testTomosDaMesmaObraPeloVolumeComSemVolumePrimeiro() {
        let grupos = AgrupamentoPorPrateleira.agrupar([
            livro("Tratado de direito privado", volume: 48),
            livro("Tratado de direito privado", volume: 7),
            livro("Tratado de direito privado"),
            livro("Tratado de direito privado", volume: 47),
        ])

        XCTAssertEqual(grupos.first?.livros.map(\.volume), [nil, 7, 47, 48])
    }

    func testMesmoTituloSemVolumeOrdenaPeloAno() {
        let grupos = AgrupamentoPorPrateleira.agrupar([
            livro("Curso de direito civil", ano: 2012),
            livro("Curso de direito civil", ano: 1998),
        ])

        XCTAssertEqual(grupos.first?.livros.map(\.ano), [1998, 2012])
    }
}
