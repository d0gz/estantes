import XCTest
@testable import Estantes

final class RascunhoSumarioTests: XCTestCase {
    private let idPrefacio = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let idParagrafo = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    /// Prefácio em romanos, vindo de foto, e um § manual abaixo dele: id, origem, nível, numeração e página
    /// têm de voltar iguais.
    private var itensDoTomo: [ItemSumario] {
        [
            ItemSumario(id: idPrefacio, nivel: 1, titulo: "Prefácio", pagina: "XI", origem: .foto),
            ItemSumario(
                id: idParagrafo, nivel: 2, numeracao: "§ 5.108", titulo: "Conceito e natureza",
                pagina: "3", origem: .manual
            ),
        ]
    }

    // MARK: T1 — ida e volta

    func testMontarSemEdicaoDevolveOsMesmosItens() {
        let rascunho = RascunhoSumario(itens: itensDoTomo)

        XCTAssertEqual(rascunho.montar(), itensDoTomo)
    }

    // MARK: T2 — adicionar e inserir

    func testAdicionarNoFimDeSumarioVazioCriaItemManualDeNivel1() {
        var rascunho = RascunhoSumario(itens: [])

        let id = rascunho.adicionarNoFim()

        XCTAssertEqual(
            rascunho.itens,
            [RascunhoSumario.Item(id: id, nivel: 1, numeracao: "", titulo: "", pagina: "", origem: .manual)]
        )
    }

    func testAdicionarNoFimHerdaONivelDoUltimoItem() {
        var rascunho = RascunhoSumario(itens: itensDoTomo)

        let id = rascunho.adicionarNoFim()

        XCTAssertEqual(rascunho.itens.map(\.id), [idPrefacio, idParagrafo, id])
        XCTAssertEqual(rascunho.itens.last?.nivel, 2)
    }

    func testInserirAbaixoEntraLogoDepoisComONivelDoItemDeCima() {
        var rascunho = RascunhoSumario(itens: itensDoTomo)

        let id = rascunho.inserir(abaixoDe: idPrefacio)

        XCTAssertEqual(rascunho.itens.map(\.id), [idPrefacio, id, idParagrafo])
        XCTAssertEqual(rascunho.itens[1].nivel, 1)
        XCTAssertEqual(rascunho.itens[1].origem, .manual)
    }

    func testInserirAbaixoDeIdInexistenteNaoMudaNada() {
        var rascunho = RascunhoSumario(itens: itensDoTomo)

        let id = rascunho.inserir(abaixoDe: UUID())

        XCTAssertNil(id)
        XCTAssertEqual(rascunho.montar(), itensDoTomo)
    }

    // MARK: T3 — apagar, mover e atualizar

    private let idA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let idB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    private let idC = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!

    /// Três capítulos de nível 1: mover e apagar não criam salto de nível, só a ordem importa.
    private var rascunhoABC: RascunhoSumario {
        RascunhoSumario(itens: [
            ItemSumario(id: idA, nivel: 1, titulo: "A"),
            ItemSumario(id: idB, nivel: 1, titulo: "B"),
            ItemSumario(id: idC, nivel: 1, titulo: "C"),
        ])
    }

    func testApagarTiraOItemDaPosicao() {
        var rascunho = rascunhoABC

        rascunho.apagar(IndexSet(integer: 1))

        XCTAssertEqual(rascunho.itens.map(\.titulo), ["A", "C"])
    }

    func testMoverOUltimoParaOTopo() {
        var rascunho = rascunhoABC

        rascunho.mover(de: IndexSet(integer: 2), para: 0)

        XCTAssertEqual(rascunho.itens.map(\.titulo), ["C", "A", "B"])
    }

    /// Destino como o `.onMove` entrega: a posição antes de retirar o item (3 = depois do último).
    func testMoverOPrimeiroParaOFim() {
        var rascunho = rascunhoABC

        rascunho.mover(de: IndexSet(integer: 0), para: 3)

        XCTAssertEqual(rascunho.itens.map(\.titulo), ["B", "C", "A"])
    }

    /// O caso que o ajuste do destino existe para resolver: o item vem de cima e o destino fica no meio.
    func testMoverOPrimeiroParaOMeio() {
        var rascunho = rascunhoABC

        rascunho.mover(de: IndexSet(integer: 0), para: 2)

        XCTAssertEqual(rascunho.itens.map(\.titulo), ["B", "A", "C"])
    }

    func testMoverDoisItensJuntosParaOFim() {
        var rascunho = rascunhoABC

        rascunho.mover(de: IndexSet([0, 1]), para: 3)

        XCTAssertEqual(rascunho.itens.map(\.titulo), ["C", "A", "B"])
    }

    func testMoverParaDestinoForaDaListaParaNasPontas() {
        var paraOFim = rascunhoABC
        paraOFim.mover(de: IndexSet(integer: 0), para: 99)
        XCTAssertEqual(paraOFim.itens.map(\.titulo), ["B", "C", "A"])

        var paraOTopo = rascunhoABC
        paraOTopo.mover(de: IndexSet(integer: 2), para: -5)
        XCTAssertEqual(paraOTopo.itens.map(\.titulo), ["C", "A", "B"])
    }

    func testApagarVariosItensDeUmaVez() {
        var rascunho = rascunhoABC

        rascunho.apagar(IndexSet([0, 2]))

        XCTAssertEqual(rascunho.itens.map(\.titulo), ["B"])
    }

    func testAtualizarTrocaOsTextosDoItemPeloId() {
        var rascunho = rascunhoABC
        var item = rascunho.itens[1]
        item.numeracao = "Capítulo II"
        item.titulo = "Das obrigações"
        item.pagina = "45"

        rascunho.atualizar(item)

        XCTAssertEqual(
            rascunho.itens[1],
            RascunhoSumario.Item(
                id: idB, nivel: 1, numeracao: "Capítulo II", titulo: "Das obrigações", pagina: "45", origem: .manual
            )
        )
    }

    func testAtualizarItemQueNaoExisteNaoMudaNada() {
        var rascunho = rascunhoABC

        rascunho.atualizar(
            RascunhoSumario.Item(id: UUID(), nivel: 1, numeracao: "", titulo: "X", pagina: "", origem: .manual)
        )

        XCTAssertEqual(rascunho.itens.map(\.titulo), ["A", "B", "C"])
    }

    // MARK: T4 — níveis

    /// Capítulo (1) › seção (2) › § (3).
    private var rascunhoEmEscada: RascunhoSumario {
        RascunhoSumario(itens: [
            ItemSumario(id: idA, nivel: 1, titulo: "Capítulo"),
            ItemSumario(id: idB, nivel: 2, titulo: "Seção"),
            ItemSumario(id: idC, nivel: 3, titulo: "Parágrafo"),
        ])
    }

    func testNivelMaximoDoPrimeiroItemE1() {
        XCTAssertEqual(rascunhoEmEscada.nivelMaximo(id: idA), 1)
    }

    func testNivelMaximoEONivelDoAnteriorMaisUm() {
        XCTAssertEqual(rascunhoEmEscada.nivelMaximo(id: idC), 3)
    }

    func testAumentarNivelSobeUmAteOLimite() {
        var rascunho = rascunhoABC

        rascunho.aumentarNivel(id: idB)
        XCTAssertEqual(rascunho.itens.map(\.nivel), [1, 2, 1])

        rascunho.aumentarNivel(id: idB)
        XCTAssertEqual(rascunho.itens.map(\.nivel), [1, 2, 1])
    }

    func testAumentarNivelDoPrimeiroItemNaoMudaNada() {
        var rascunho = rascunhoABC

        rascunho.aumentarNivel(id: idA)

        XCTAssertEqual(rascunho.itens.map(\.nivel), [1, 1, 1])
    }

    func testDiminuirNivelNaoPassaDe1() {
        var rascunho = rascunhoABC

        rascunho.diminuirNivel(id: idB)

        XCTAssertEqual(rascunho.itens.map(\.nivel), [1, 1, 1])
    }

    /// Nada é corrigido sozinho: o § fica no nível 3, agora com salto, que a validação vai apontar.
    func testDiminuirNivelNaoMexeNosFilhos() {
        var rascunho = rascunhoEmEscada

        rascunho.diminuirNivel(id: idB)

        XCTAssertEqual(rascunho.itens.map(\.nivel), [1, 1, 3])
    }

    /// Com a seção apagada, o § ficou acima do limite (3 depois de 1): "Nível →" não o rebaixa em silêncio.
    func testAumentarNivelNaoRebaixaItemQueJaPassouDoLimite() {
        var rascunho = rascunhoEmEscada
        rascunho.apagar(IndexSet(integer: 1))

        rascunho.aumentarNivel(id: idC)

        XCTAssertEqual(rascunho.itens.map(\.nivel), [1, 3])
    }

    // MARK: T5 — limpeza ao montar

    func testMontarLimpaEspacosEQuebrasDosTextos() {
        var rascunho = RascunhoSumario(itens: [])
        let id = rascunho.adicionarNoFim()
        rascunho.atualizar(
            RascunhoSumario.Item(
                id: id, nivel: 1, numeracao: "  Capítulo   II ", titulo: "Das\n  obrigações ", pagina: " 45 ",
                origem: .manual
            )
        )

        XCTAssertEqual(
            rascunho.montar(),
            [ItemSumario(id: id, nivel: 1, numeracao: "Capítulo II", titulo: "Das obrigações", pagina: "45")]
        )
    }

    func testMontarTrocaNumeracaoEPaginaEmBrancoPorNil() {
        var rascunho = RascunhoSumario(itens: [])
        let id = rascunho.adicionarNoFim()
        rascunho.atualizar(
            RascunhoSumario.Item(id: id, nivel: 1, numeracao: "   ", titulo: "Introdução", pagina: "", origem: .manual)
        )

        XCTAssertEqual(rascunho.montar(), [ItemSumario(id: id, nivel: 1, numeracao: nil, titulo: "Introdução")])
    }

    // MARK: T6 — validação ao montar

    /// Título só de espaços conta como vazio: a validação olha o texto já limpo.
    func testTituloEmBrancoEErroENaoMonta() {
        var rascunho = rascunhoABC
        var item = rascunho.itens[1]
        item.titulo = "   "
        rascunho.atualizar(item)

        XCTAssertEqual(rascunho.validacao().erros, [.tituloVazio(indice: 1)])
        XCTAssertNil(rascunho.montar())
    }

    /// Apagar a seção deixa o § (nível 3) logo depois do capítulo (nível 1).
    func testSaltoDeNivelDepoisDeApagarOPaiEErroENaoMonta() {
        var rascunho = rascunhoEmEscada
        rascunho.apagar(IndexSet(integer: 1))

        XCTAssertEqual(rascunho.validacao().erros, [.saltoDeNivel(indice: 1)])
        XCTAssertNil(rascunho.montar())
    }

    /// Página que volta (45 → 12) é só aviso: o sumário monta.
    func testPaginaMenorQueAAnteriorEAvisoEMontaMesmoAssim() {
        let rascunho = RascunhoSumario(itens: [
            ItemSumario(id: idA, nivel: 1, titulo: "A", pagina: "45"),
            ItemSumario(id: idB, nivel: 1, titulo: "B", pagina: "12"),
        ])

        XCTAssertEqual(
            rascunho.validacao(),
            ValidacaoSumario.Resultado(erros: [], avisos: [.paginaMenorQueAnterior(indice: 1)])
        )
        XCTAssertEqual(rascunho.montar(), [
            ItemSumario(id: idA, nivel: 1, titulo: "A", pagina: "45"),
            ItemSumario(id: idB, nivel: 1, titulo: "B", pagina: "12"),
        ])
    }
}
