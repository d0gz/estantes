import XCTest
@testable import Estantes

final class MotorDeBuscaTests: XCTestCase {
    private let estante1 = UUID()
    private let estante2 = UUID()

    private lazy var livroA = Livro(
        estanteId: estante1,
        titulo: "Prisão preventiva",
        itensSumario: [ItemSumario(nivel: 1, titulo: "Prisão em flagrante")]
    )
    private lazy var livroB = Livro(
        estanteId: estante1,
        titulo: "Processo penal",
        itensSumario: ["Prisão", "Recursos", "Provas"].map { ItemSumario(nivel: 1, titulo: $0) }
    )
    private lazy var livroC = Livro(estanteId: estante2, titulo: "Direito civil", editora: "Saraiva")
    private lazy var livroD = Livro(estanteId: estante2, titulo: "Prevenção de litígios")
    private lazy var motor = MotorDeBusca(livros: [livroA, livroB, livroC, livroD], categorias: [])

    private func ids(_ resultados: [ResultadoBusca]) -> [UUID] {
        resultados.map { $0.livro.id }
    }

    private func nota(de livro: Livro, em resultados: [ResultadoBusca]) -> Double? {
        resultados.first { $0.livro.id == livro.id }?.nota
    }

    // MARK: - E entre os termos

    func testExigeTodosOsTermos() {
        XCTAssertEqual(ids(motor.buscar("prisão preventiva")), [livroA.id])
        XCTAssertEqual(ids(motor.buscar("prisão civil")), [])
    }

    func testOrdenaPelaNota() {
        // A tem "prisão" no título (peso 3); B, só no sumário.
        XCTAssertEqual(ids(motor.buscar("prisao")), [livroA.id, livroB.id])
    }

    // MARK: - Prefixo

    func testUltimoTermoValeComoPrefixo() {
        XCTAssertEqual(ids(motor.buscar("prevent")), [livroA.id])
        XCTAssertEqual(ids(motor.buscar("prevenc")), [livroD.id])
        XCTAssertEqual(Set(ids(motor.buscar("prev"))), [livroA.id, livroD.id])
    }

    func testSoOUltimoTermoValeComoPrefixo() {
        XCTAssertEqual(ids(motor.buscar("prisao prevent")), [livroA.id])
        XCTAssertEqual(ids(motor.buscar("prevent prisao")), [])
    }

    func testPrefixoDeUmaLetraNaoExpande() {
        XCTAssertEqual(ids(motor.buscar("c")), [])
        XCTAssertEqual(ids(motor.buscar("ci")), [livroC.id])
    }

    func testPrefixoFicaComAMaiorNotaEntreAsExpansoes() {
        let livro = Livro(estanteId: estante1, titulo: "Prevenção preventiva")
        let motor = MotorDeBusca(livros: [livro, livroC], categorias: [])

        let prefixo = nota(de: livro, em: motor.buscar("prev")) ?? 0
        let prevencao = nota(de: livro, em: motor.buscar("prevencao")) ?? 0
        let preventiva = nota(de: livro, em: motor.buscar("preventiva")) ?? 0

        XCTAssertGreaterThan(prevencao, 0)
        XCTAssertEqual(prefixo, max(prevencao, preventiva))
        XCTAssertLessThan(prefixo, prevencao + preventiva)
    }

    func testTermoRepetidoContaUmaVez() {
        XCTAssertEqual(motor.buscar("penal penal"), motor.buscar("penal"))
        XCTAssertEqual(motor.buscar("prisao penal prisao"), motor.buscar("penal prisao"))
    }

    func testUltimoTermoRepetidoNaoExpande() {
        // "prev" não é termo do vocabulário: repetido, vale como exato e não acha nada.
        XCTAssertEqual(Set(ids(motor.buscar("prev"))), [livroA.id, livroD.id])
        XCTAssertEqual(ids(motor.buscar("prev prev")), [])
    }

    // MARK: - Filtro

    func testFiltroQueAceitaTodosNaoMudaNada() {
        let semFiltro = motor.buscar("prisao")

        // A e B estão na estante 1.
        XCTAssertEqual(motor.buscar("prisao", filtro: FiltroBusca(estanteIds: [estante1])), semFiltro)
        XCTAssertEqual(motor.buscar("prisao", filtro: FiltroBusca(estanteIds: [estante2])), [])
    }

    func testFiltroDeAutorCDDirECategoriaComConsulta() {
        let penal = UUID()
        var a = livroA
        a.autores = ["Nucci, Guilherme de Souza"]
        a.cddir = "341.43"
        a.categoriaIds = [penal]
        var motor = self.motor
        motor.atualizar(a)

        XCTAssertEqual(ids(motor.buscar("prisao", filtro: FiltroBusca(autor: "nucci"))), [livroA.id])
        XCTAssertEqual(ids(motor.buscar("prisao", filtro: FiltroBusca(prefixoCDDir: "341.4"))), [livroA.id])
        XCTAssertEqual(ids(motor.buscar("prisao", filtro: FiltroBusca(categoriaIds: [penal]))), [livroA.id])
        XCTAssertEqual(ids(motor.buscar("prisao", filtro: FiltroBusca(autor: "nucci", prefixoCDDir: "342"))), [])
    }

    func testFiltroTiraLivroSemMudarANotaDosOutros() {
        var livroBComAno = livroB
        livroBComAno.ano = 2020
        var motor = self.motor
        motor.atualizar(livroBComAno)

        let semFiltro = motor.buscar("prisao")
        let comFiltro = motor.buscar("prisao", filtro: FiltroBusca(anoMinimo: 2000))

        XCTAssertEqual(ids(comFiltro), [livroB.id])
        XCTAssertEqual(nota(de: livroB, em: comFiltro), nota(de: livroB, em: semFiltro))
    }

    // MARK: - Consulta vazia

    func testConsultaVaziaSemFiltroNaoDevolveNada() {
        XCTAssertEqual(motor.buscar(""), [])
        XCTAssertEqual(motor.buscar("   "), [])
        XCTAssertEqual(motor.buscar("de"), [])
    }

    func testConsultaSoComPalavraVaziaEFiltroListaPeloFiltro() {
        let filtro = FiltroBusca(estanteIds: [estante2])

        XCTAssertEqual(motor.buscar("de", filtro: filtro), motor.buscar("", filtro: filtro))
    }

    func testConsultaVaziaComFiltroListaEmOrdemDeTitulo() {
        let resultados = motor.buscar("", filtro: FiltroBusca(estanteIds: [estante2]))

        // "Direito civil" antes de "Prevenção de litígios"
        XCTAssertEqual(ids(resultados), [livroC.id, livroD.id])
        XCTAssertTrue(resultados.allSatisfy { $0.nota == 0 })
    }

    // MARK: - Ordem

    func testEmpateDeNotaVaiPeloTitulo() {
        let zeta = Livro(estanteId: estante1, titulo: "Zeta civil")
        let alfa = Livro(estanteId: estante1, titulo: "Alfa civil")
        let motor = MotorDeBusca(livros: [zeta, alfa], categorias: [])

        let resultados = motor.buscar("civil")

        XCTAssertEqual(resultados.map(\.nota)[0], resultados.map(\.nota)[1])
        XCTAssertEqual(ids(resultados), [alfa.id, zeta.id])
    }

    // MARK: - Alteração

    func testAtualizarReindexaOLivro() {
        var motor = self.motor
        var renomeado = livroC
        renomeado.titulo = "Direito tributário"
        motor.atualizar(renomeado)

        XCTAssertEqual(ids(motor.buscar("tributario")), [livroC.id])
        XCTAssertEqual(ids(motor.buscar("civil")), [])
        XCTAssertEqual(motor.buscar("tributario").first?.livro, renomeado)
    }

    func testRemoverTiraDaBuscaEDaListagemPorFiltro() {
        var motor = self.motor
        motor.remover(livroId: livroC.id)

        XCTAssertEqual(ids(motor.buscar("civil")), [])
        XCTAssertEqual(ids(motor.buscar("", filtro: FiltroBusca(estanteIds: [estante2]))), [livroD.id])
    }

    func testRemoverIdAusenteNaoFazNada() {
        var motor = self.motor
        motor.remover(livroId: UUID())

        XCTAssertEqual(ids(motor.buscar("prisao")), [livroA.id, livroB.id])
    }

    func testCategoriaEntraNaBuscaPeloNome() {
        let penal = Categoria(nome: "Criminal", cor: .vermelho)
        var livro = livroB
        livro.categoriaIds = [penal.id]
        let motor = MotorDeBusca(livros: [livro, livroC], categorias: [penal])

        XCTAssertEqual(ids(motor.buscar("criminal")), [livro.id])
    }
}
