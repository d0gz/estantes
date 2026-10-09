import XCTest
@testable import Estantes

/// Testes da régua: uma métrica errada engana o ajuste dos pesos inteiro sem dar sinal.
final class MetricasDeBuscaTests: XCTestCase {
    private let estante = UUID()

    private func livro(_ titulo: String, itens: [ItemSumario] = []) -> Livro {
        Livro(estanteId: estante, titulo: titulo, itensSumario: itens)
    }

    private func resultado(_ livro: Livro, _ nota: Double, item: ItemSumario? = nil) -> ResultadoBusca {
        ResultadoBusca(livro: livro, itemDoSumario: item, nota: nota)
    }

    private func consulta(item: String? = nil, tipo: ConsultaDeReferencia.Tipo = .ajuste) -> ConsultaDeReferencia {
        ConsultaDeReferencia("x", esperado: "x", item: item, caso: .titulo, tipo: tipo)
    }

    private func medicao(
        posicao: Int?,
        item: String? = nil,
        mostrado: ItemSumario? = nil,
        tipo: ConsultaDeReferencia.Tipo = .ajuste
    ) -> MedicaoDeConsulta {
        MedicaoDeConsulta(consulta: consulta(item: item, tipo: tipo), posicao: posicao, nota: nil, itemMostrado: mostrado)
    }

    // MARK: - Posição

    func testPosicaoContaQuemTemNotaMaior() {
        let a = livro("A"), b = livro("B"), c = livro("C")
        let resultados = [resultado(a, 3), resultado(b, 2), resultado(c, 1)]
        XCTAssertEqual(MetricasDeBusca.posicao(de: a.id, em: resultados), 1)
        XCTAssertEqual(MetricasDeBusca.posicao(de: c.id, em: resultados), 3)
    }

    func testLivroAusenteNaoTemPosicao() {
        let a = livro("A")
        XCTAssertNil(MetricasDeBusca.posicao(de: UUID(), em: [resultado(a, 1)]))
        XCTAssertNil(MetricasDeBusca.posicao(de: a.id, em: []))
    }

    func testEmpateEhPessimista() {
        // O motor põe "A" antes de "B" pela ordem alfabética, mas isso não é mérito de relevância:
        // com a mesma nota, os dois ficam na 2ª posição.
        let a = livro("A"), b = livro("B")
        let resultados = [resultado(a, 2), resultado(b, 2)]
        XCTAssertEqual(MetricasDeBusca.posicao(de: a.id, em: resultados), 2)
        XCTAssertEqual(MetricasDeBusca.posicao(de: b.id, em: resultados), 2)
    }

    func testDiferencaDeArredondamentoContaComoEmpate() {
        let a = livro("A"), b = livro("B")
        let resultados = [resultado(a, 0.3), resultado(b, 0.1 + 0.2)]  // 0.30000000000000004
        XCTAssertEqual(MetricasDeBusca.posicao(de: b.id, em: resultados), 2)
    }

    // MARK: - Agregados

    func testTop1Top3EMRR() {
        let avaliacao = AvaliacaoDaBusca(medicoes: [
            medicao(posicao: 1), medicao(posicao: 2), medicao(posicao: 4), medicao(posicao: nil)
        ])
        XCTAssertEqual(avaliacao.top1, 0.25)
        XCTAssertEqual(avaliacao.top3, 0.5)
        // (1 + 1/2 + 1/4 + 0) / 4
        XCTAssertEqual(avaliacao.mrr, 0.4375, accuracy: 1e-12)
    }

    func testSondasFicamForaDasMedias() {
        let avaliacao = AvaliacaoDaBusca(medicoes: [medicao(posicao: 1), medicao(posicao: nil, tipo: .sonda)])
        XCTAssertEqual(avaliacao.top1, 1)
        XCTAssertEqual(avaliacao.mrr, 1)
        XCTAssertEqual(avaliacao.medicoes.count, 2)
    }

    func testConjuntoVazioDaZero() {
        let avaliacao = AvaliacaoDaBusca(medicoes: [])
        XCTAssertEqual(avaliacao.top1, 0)
        XCTAssertEqual(avaliacao.top3, 0)
        XCTAssertEqual(avaliacao.mrr, 0)
        XCTAssertNil(avaliacao.itemCerto)
    }

    // MARK: - Item do sumário

    func testItemCasaPelaNumeracaoOuPeloTitulo() {
        let item = ItemSumario(nivel: 1, numeracao: "Art. 1.710", titulo: "Da sub-rogação")
        XCTAssertEqual(medicao(posicao: 1, item: "Art. 1.710", mostrado: item).itemCerto, true)
        XCTAssertEqual(medicao(posicao: 1, item: "Da sub-rogação", mostrado: item).itemCerto, true)
        XCTAssertEqual(medicao(posicao: 1, item: "Art. 1.711", mostrado: item).itemCerto, false)
        XCTAssertEqual(medicao(posicao: 1, item: "Art. 1.710", mostrado: nil).itemCerto, false)
    }

    func testItemSoContaComLivroNoTop3() {
        XCTAssertNil(medicao(posicao: 4, item: "Art. 1.710").itemCerto)
        XCTAssertNil(medicao(posicao: nil, item: "Art. 1.710").itemCerto)
        XCTAssertNil(medicao(posicao: 1).itemCerto)  // a consulta não espera item

        let item = ItemSumario(nivel: 1, titulo: "Prisão")
        let avaliacao = AvaliacaoDaBusca(medicoes: [
            medicao(posicao: 1, item: "Prisão", mostrado: item),
            medicao(posicao: 2, item: "Fiança", mostrado: item),
            medicao(posicao: 9, item: "Prisão")
        ])
        XCTAssertEqual(avaliacao.itemCerto, 0.5)
    }

    // MARK: - Avaliar no motor

    func testAvaliarRodaCadaConsultaNoMotor() {
        let a = livro("Prisão preventiva")
        let b = livro("Processo penal", itens: [ItemSumario(nivel: 1, titulo: "Prisão em flagrante")])
        let motor = MotorDeBusca(livros: [a, b], categorias: [])
        let consultas = [
            ConsultaDeReferencia("prisao", esperado: "b", caso: .sumario),
            ConsultaDeReferencia("flagrante", esperado: "b", item: "Prisão em flagrante", caso: .sumario)
        ]

        let avaliacao = MetricasDeBusca.avaliar(consultas, motor: motor, ids: ["a": a.id, "b": b.id])

        XCTAssertEqual(avaliacao.medicoes.map(\.posicao), [2, 1])  // título de A pesa mais
        XCTAssertEqual(avaliacao.mrr, 0.75)
        XCTAssertEqual(avaliacao.itemCerto, 1)
    }
}
