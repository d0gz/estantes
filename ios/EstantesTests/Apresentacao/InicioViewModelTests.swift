import XCTest
@testable import Estantes

/// O `InicioViewModel` com o repositório falso: sem banco, sem tela.
@MainActor
final class InicioViewModelTests: XCTestCase {
    private let sala = Estante(nome: "Sala", criadaEm: Date(timeIntervalSinceReferenceDate: 1))
    private let escritorio = Estante(nome: "Escritório", criadaEm: Date(timeIntervalSinceReferenceDate: 2))

    private func livro(em estante: Estante) -> Livro {
        Livro(estanteId: estante.id, titulo: "Teoria pura do direito")
    }

    func testComecaCarregando() {
        let viewModel = InicioViewModel(repositorio: BibliotecaRepositorioEmMemoria())
        XCTAssertEqual(viewModel.estado, .carregando)
    }

    func testCarregaAsEstantesComAQuantidadeDeLivros() async {
        let repositorio = BibliotecaRepositorioEmMemoria(
            estantes: [sala, escritorio],
            livros: [livro(em: sala), livro(em: sala)]
        )
        let viewModel = InicioViewModel(repositorio: repositorio)

        await viewModel.carregar()

        XCTAssertEqual(viewModel.estado, .pronto([
            EstanteResumo(estante: sala, quantidadeDeLivros: 2),
            EstanteResumo(estante: escritorio, quantidadeDeLivros: 0),
        ]))
    }

    func testSemEstantesFicaVazio() async {
        let viewModel = InicioViewModel(repositorio: BibliotecaRepositorioEmMemoria())
        await viewModel.carregar()
        XCTAssertEqual(viewModel.estado, .vazio)
    }

    func testFalhaAoLerViraEstadoDeErro() async {
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [sala])
        repositorio.falharAoLer = true
        let viewModel = InicioViewModel(repositorio: repositorio)

        await viewModel.carregar()

        XCTAssertEqual(viewModel.estado, .erro("Não foi possível carregar as estantes."))
    }

    func testCriaEstanteComNomeAparadoERecarrega() async {
        let repositorio = BibliotecaRepositorioEmMemoria()
        let viewModel = InicioViewModel(repositorio: repositorio)

        await viewModel.criarEstante(nome: "  Biblioteca do escritório \n")

        XCTAssertEqual(repositorio.estantesGuardadas.values.map(\.nome), ["Biblioteca do escritório"])
        guard case .pronto(let resumos) = viewModel.estado else {
            return XCTFail("Esperava a lista recarregada, veio \(viewModel.estado)")
        }
        XCTAssertEqual(resumos.map(\.estante.nome), ["Biblioteca do escritório"])
    }

    func testNaoCriaEstanteComNomeSoDeEspacos() async {
        let repositorio = BibliotecaRepositorioEmMemoria()
        let viewModel = InicioViewModel(repositorio: repositorio)

        await viewModel.criarEstante(nome: "   ")

        XCTAssertTrue(repositorio.estantesGuardadas.isEmpty)
    }

    func testRenomeiaMantendoIdEData() async {
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [sala])
        let viewModel = InicioViewModel(repositorio: repositorio)

        await viewModel.renomear(sala, para: " Sala de estar ")

        let renomeada = repositorio.estantesGuardadas[sala.id]
        XCTAssertEqual(renomeada?.nome, "Sala de estar")
        XCTAssertEqual(renomeada?.criadaEm, sala.criadaEm)
        XCTAssertEqual(repositorio.estantesGuardadas.count, 1)
    }

    func testRenomearComNomeVazioNaoMudaNada() async {
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [sala])
        let viewModel = InicioViewModel(repositorio: repositorio)

        await viewModel.renomear(sala, para: "  ")

        XCTAssertEqual(repositorio.estantesGuardadas[sala.id]?.nome, "Sala")
    }

    func testFalhaAoGravarMostraMensagemEMantemALista() async {
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [sala])
        repositorio.falharAoGravar = true
        let viewModel = InicioViewModel(repositorio: repositorio)

        await viewModel.criarEstante(nome: "Escritório")

        XCTAssertEqual(viewModel.mensagemDeErro, "Não foi possível criar a estante.")
        XCTAssertEqual(viewModel.estado, .pronto([EstanteResumo(estante: sala, quantidadeDeLivros: 0)]))
    }

    // MARK: Apagar estante

    func testPedidoDeExclusaoTrazQuantidadeEOutrasEstantes() async {
        let tratados = Estante(nome: "Tratados", criadaEm: Date(timeIntervalSinceReferenceDate: 3))
        let repositorio = BibliotecaRepositorioEmMemoria(
            estantes: [sala, escritorio, tratados],
            livros: [livro(em: sala), livro(em: sala), livro(em: escritorio)]
        )
        let viewModel = InicioViewModel(repositorio: repositorio)

        let pedido = await viewModel.pedidoDeExclusao(de: sala)

        XCTAssertEqual(pedido?.quantidadeDeLivros, 2)
        XCTAssertEqual(pedido?.destinosPossiveis, [escritorio, tratados])
        XCTAssertEqual(pedido?.podeMover, true)
    }

    func testEstanteVaziaNaoOfereceMover() async {
        let viewModel = InicioViewModel(repositorio: BibliotecaRepositorioEmMemoria(estantes: [sala, escritorio]))

        let pedido = await viewModel.pedidoDeExclusao(de: sala)

        XCTAssertEqual(pedido?.quantidadeDeLivros, 0)
        XCTAssertEqual(pedido?.podeMover, false)
    }

    func testSemOutraEstanteNaoOfereceMover() async {
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [sala], livros: [livro(em: sala)])
        let viewModel = InicioViewModel(repositorio: repositorio)

        let pedido = await viewModel.pedidoDeExclusao(de: sala)

        XCTAssertEqual(pedido?.destinosPossiveis, [])
        XCTAssertEqual(pedido?.podeMover, false)
    }

    func testFalhaAoPrepararExclusaoMostraMensagem() async {
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [sala])
        repositorio.falharAoLer = true
        let viewModel = InicioViewModel(repositorio: repositorio)

        let pedido = await viewModel.pedidoDeExclusao(de: sala)

        XCTAssertNil(pedido)
        XCTAssertEqual(viewModel.mensagemDeErro, "Não foi possível preparar a exclusão da estante.")
    }

    func testApagarSemDestinoLevaOsLivrosJunto() async {
        let repositorio = BibliotecaRepositorioEmMemoria(
            estantes: [sala, escritorio], livros: [livro(em: sala), livro(em: escritorio)]
        )
        let viewModel = InicioViewModel(repositorio: repositorio)
        let pedido = await viewModel.pedidoDeExclusao(de: sala)!

        await viewModel.apagar(pedido, movendoLivrosPara: nil)

        XCTAssertNil(repositorio.estantesGuardadas[sala.id])
        XCTAssertEqual(repositorio.livrosGuardados.values.map(\.estanteId), [escritorio.id])
        XCTAssertEqual(viewModel.estado, .pronto([EstanteResumo(estante: escritorio, quantidadeDeLivros: 1)]))
    }

    func testApagarMovendoLevaOsLivrosParaODestino() async {
        let repositorio = BibliotecaRepositorioEmMemoria(
            estantes: [sala, escritorio], livros: [livro(em: sala), livro(em: sala)]
        )
        let viewModel = InicioViewModel(repositorio: repositorio)
        let pedido = await viewModel.pedidoDeExclusao(de: sala)!

        await viewModel.apagar(pedido, movendoLivrosPara: escritorio)

        XCTAssertNil(repositorio.estantesGuardadas[sala.id])
        XCTAssertEqual(repositorio.livrosGuardados.count, 2)
        XCTAssertTrue(repositorio.livrosGuardados.values.allSatisfy { $0.estanteId == escritorio.id })
        XCTAssertEqual(viewModel.estado, .pronto([EstanteResumo(estante: escritorio, quantidadeDeLivros: 2)]))
    }

    func testFalhaAoApagarMostraMensagemEMantemAEstante() async {
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [sala])
        let viewModel = InicioViewModel(repositorio: repositorio)
        let pedido = await viewModel.pedidoDeExclusao(de: sala)!
        repositorio.falharAoGravar = true

        await viewModel.apagar(pedido, movendoLivrosPara: nil)

        XCTAssertEqual(viewModel.mensagemDeErro, "Não foi possível apagar a estante.")
        XCTAssertNotNil(repositorio.estantesGuardadas[sala.id])
    }

    func testNomeValido() {
        XCTAssertEqual(InicioViewModel.nomeValido("  Sala  "), "Sala")
        XCTAssertNil(InicioViewModel.nomeValido(" \n "))
    }

    func testTextoDaQuantidadeNoSingularENoPlural() {
        XCTAssertEqual(InicioView.textoDaQuantidade(0), "0 livros")
        XCTAssertEqual(InicioView.textoDaQuantidade(1), "1 livro")
        XCTAssertEqual(InicioView.textoDaQuantidade(12), "12 livros")
        XCTAssertEqual(InicioView.textoDaQuantidade(1, comArtigo: true), "o livro")
        XCTAssertEqual(InicioView.textoDaQuantidade(3, comArtigo: true), "os 3 livros")
    }
}
