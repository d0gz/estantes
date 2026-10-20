import XCTest
@testable import Estantes

/// A busca do Inicio, com a `BibliotecaIndexada` de verdade sobre o repositório falso.
@MainActor
final class BuscaViewModelTests: XCTestCase {
    private let escritorio = Estante(nome: "Escritório", criadaEm: Date(timeIntervalSinceReferenceDate: 1))
    private let sala = Estante(nome: "Sala", criadaEm: Date(timeIntervalSinceReferenceDate: 2))
    private lazy var lassalle = Livro(
        estanteId: escritorio.id, titulo: "A essência da constituição", autores: ["Lassalle, Ferdinand"]
    )
    private lazy var pontes = Livro(
        estanteId: sala.id, titulo: "Tratado de direito privado", autores: ["Pontes de Miranda"]
    )
    private lazy var base = BibliotecaRepositorioEmMemoria(estantes: [escritorio, sala], livros: [lassalle, pontes])
    private lazy var viewModel = BuscaViewModel(biblioteca: BibliotecaIndexada(base: base))

    func testTextoVazioSemFiltroMostraADica() async {
        viewModel.texto = "  "

        await viewModel.buscar()

        XCTAssertEqual(viewModel.estado, .dica)
    }

    func testTextoQueAchaMostraOsResultados() async {
        viewModel.texto = "lassalle"

        await viewModel.buscar()

        XCTAssertEqual(ids(viewModel.estado), [lassalle.id])
    }

    func testTextoQueNaoAchaNadaMostraNadaEncontrado() async {
        viewModel.texto = "xyzw"

        await viewModel.buscar()

        XCTAssertEqual(viewModel.estado, .nadaEncontrado)
    }

    func testSoComFiltroListaOsLivrosQuePassamNele() async {
        viewModel.filtro.estanteIds = [sala.id]

        await viewModel.buscar()

        XCTAssertEqual(ids(viewModel.estado), [pontes.id])
    }

    // MARK: - Correção

    func testErroDeDigitacaoECorrigidoEBuscarExatamenteDesliga() async {
        viewModel.texto = "lassale"
        await viewModel.buscar()
        XCTAssertEqual(ids(viewModel.estado), [lassalle.id])
        XCTAssertEqual(correcoes(viewModel.estado), [Correcao(digitado: "lassale", usado: "lassalle")])

        viewModel.buscarExatamente()
        await viewModel.buscar()

        XCTAssertEqual(viewModel.estado, .nadaEncontrado)
    }

    func testMudarOTextoDepoisDeBuscarExatamenteVoltaACorrigir() async {
        viewModel.texto = "lassale"
        viewModel.buscarExatamente()

        viewModel.texto = "lassale "
        await viewModel.buscar()

        XCTAssertEqual(ids(viewModel.estado), [lassalle.id])
    }

    func testFalhaAoPrepararOIndiceMostraOErro() async {
        base.falharAoLer = true
        viewModel.texto = "lassalle"

        await viewModel.buscar()

        XCTAssertEqual(viewModel.estado, .erro("Não foi possível preparar a busca."))
    }

    // MARK: - Filtros

    func testAlternarDuasVezesDesmarcaAEstanteEACategoria() {
        let civil = Categoria(nome: "Civil", cor: .laranja)

        viewModel.alternar(estante: sala.id)
        viewModel.alternar(categoria: civil.id)
        XCTAssertEqual(viewModel.filtro, FiltroBusca(estanteIds: [sala.id], categoriaIds: [civil.id]))
        viewModel.alternar(estante: sala.id)
        viewModel.alternar(categoria: civil.id)

        XCTAssertEqual(viewModel.filtro, FiltroBusca())
    }

    func testQuantidadeNaFolhaContaAutorEditoraEAnosComoUm() {
        viewModel.filtro = FiltroBusca(autor: "Pontes", editora: "Borsoi", anoMinimo: 1954, anoMaximo: 1972)
        XCTAssertEqual(viewModel.quantidadeNaFolha, 3)

        viewModel.filtro = FiltroBusca(anoMaximo: 1972)
        XCTAssertEqual(viewModel.quantidadeNaFolha, 1)
    }

    // O `FiltroBusca` trata texto em branco como "sem filtro": o chip não pode dizer o contrário.
    // Estantes e categorias não contam: os chips delas mostram a seleção.
    func testQuantidadeNaFolhaIgnoraTextoEmBrancoEOsChips() {
        viewModel.filtro = FiltroBusca(autor: "  ", editora: "", estanteIds: [sala.id])

        XCTAssertEqual(viewModel.quantidadeNaFolha, 0)
    }

    func testCarregarOpcoesTrazAsEstantesEAsCategoriasDosChips() async throws {
        let civil = Categoria(nome: "Civil", cor: .laranja)
        try await base.salvar(civil)

        await viewModel.carregarOpcoes()

        XCTAssertEqual(viewModel.estantes, [escritorio, sala])
        XCTAssertEqual(viewModel.categorias, [civil])
        XCTAssertEqual(viewModel.nomeDaEstante(pontes.estanteId), "Sala")
        XCTAssertNil(viewModel.nomeDaEstante(UUID()))
    }

    func testCarregarOpcoesTiraDoFiltroAEstanteEACategoriaQueNaoExistemMais() async throws {
        let civil = Categoria(nome: "Civil", cor: .laranja)
        let apagada = Categoria(nome: "Penal", cor: .amarelo)
        try await base.salvar(civil)
        viewModel.filtro = FiltroBusca(estanteIds: [sala.id, UUID()], categoriaIds: [civil.id, apagada.id])

        await viewModel.carregarOpcoes()

        XCTAssertEqual(viewModel.filtro, FiltroBusca(estanteIds: [sala.id], categoriaIds: [civil.id]))
    }

    private func correcoes(_ estado: BuscaViewModel.Estado) -> [Correcao]? {
        guard case let .resultados(resposta) = estado else { return nil }
        return resposta.correcoes
    }

    /// Os livros da lista, ou `nil` se o estado não é `.resultados`.
    private func ids(_ estado: BuscaViewModel.Estado) -> [UUID]? {
        guard case let .resultados(resposta) = estado else { return nil }
        return resposta.resultados.map { $0.livro.id }
    }
}
