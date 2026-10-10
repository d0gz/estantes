import XCTest
@testable import Estantes

@MainActor
final class LivroFormularioViewModelTests: XCTestCase {
    private let escritorio = Estante(nome: "Escritório", criadaEm: Date(timeIntervalSinceReferenceDate: 1))
    private let sala = Estante(nome: "Sala", criadaEm: Date(timeIntervalSinceReferenceDate: 2))

    private func livroImportado() -> Livro {
        Livro(
            estanteId: escritorio.id, titulo: "Tratado de direito privado", autores: ["Miranda, Pontes de"],
            editora: "Borsoi", ano: 1965, urn: "urn:lex:br:1965", origem: .lexml,
            itensSumario: [ItemSumario(nivel: 1, titulo: "Do casamento")]
        )
    }

    private func preencherObrigatorios(_ viewModel: LivroFormularioViewModel) {
        viewModel.rascunho.titulo = "Teoria pura do direito"
        viewModel.rascunho.autores = ["Kelsen, Hans"]
        viewModel.rascunho.editora = "Martins Fontes"
        viewModel.rascunho.ano = "1998"
    }

    // MARK: Novo livro

    func testNovoCarregaAsEstantesEComecaNaEstanteDeOrigem() async {
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [escritorio, sala])
        let viewModel = LivroFormularioViewModel(modo: .novo(estanteId: sala.id), repositorio: repositorio)

        await viewModel.carregar()

        XCTAssertEqual(viewModel.estado, .pronto)
        XCTAssertEqual(viewModel.estantes, [escritorio, sala])
        XCTAssertEqual(viewModel.rascunho.estanteId, sala.id)
        XCTAssertEqual(viewModel.titulo, "Novo livro")
        XCTAssertFalse(viewModel.alterado)
    }

    func testErrosSoAparecemDepoisDeTentarSalvar() async {
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [escritorio])
        let viewModel = LivroFormularioViewModel(modo: .novo(estanteId: escritorio.id), repositorio: repositorio)
        await viewModel.carregar()

        XCTAssertEqual(viewModel.problemas, [:])
        let salvou = await viewModel.salvar()

        XCTAssertFalse(salvou)
        XCTAssertEqual(viewModel.problemas[.titulo], .obrigatorio)
        XCTAssertTrue(repositorio.livrosGuardados.isEmpty)
    }

    func testSalvarNovoGravaOLivro() async throws {
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [escritorio])
        let viewModel = LivroFormularioViewModel(modo: .novo(estanteId: escritorio.id), repositorio: repositorio)
        await viewModel.carregar()
        preencherObrigatorios(viewModel)

        XCTAssertTrue(viewModel.alterado)
        let salvou = await viewModel.salvar()

        XCTAssertTrue(salvou)
        let gravado = try XCTUnwrap(repositorio.livrosGuardados.values.first)
        XCTAssertEqual(gravado.titulo, "Teoria pura do direito")
        XCTAssertEqual(gravado.origem, .manual)
        XCTAssertEqual(gravado.estanteId, escritorio.id)
    }

    func testFalhaAoGravarMostraMensagemENaoFecha() async {
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [escritorio])
        let viewModel = LivroFormularioViewModel(modo: .novo(estanteId: escritorio.id), repositorio: repositorio)
        await viewModel.carregar()
        preencherObrigatorios(viewModel)
        repositorio.falharAoGravar = true

        let salvou = await viewModel.salvar()

        XCTAssertFalse(salvou)
        XCTAssertEqual(viewModel.mensagemDeErro, "Não foi possível salvar o livro.")
        XCTAssertFalse(viewModel.salvando)
    }

    func testFalhaAoCarregarViraErro() async {
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [escritorio])
        repositorio.falharAoLer = true
        let viewModel = LivroFormularioViewModel(modo: .novo(estanteId: escritorio.id), repositorio: repositorio)

        await viewModel.carregar()

        XCTAssertEqual(viewModel.estado, .erro("Não foi possível abrir o formulário."))
    }

    // MARK: Edição

    func testEdicaoCarregaOLivroNoRascunho() async {
        let livro = livroImportado()
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [escritorio], livros: [livro])
        let viewModel = LivroFormularioViewModel(modo: .edicao(livroId: livro.id), repositorio: repositorio)

        await viewModel.carregar()

        XCTAssertEqual(viewModel.rascunho, RascunhoLivro(livro: livro))
        XCTAssertEqual(viewModel.titulo, "Editar livro")
        XCTAssertFalse(viewModel.alterado)
    }

    func testEdicaoMoveDeEstanteEPreservaSumarioEOrigem() async throws {
        let livro = livroImportado()
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [escritorio, sala], livros: [livro])
        let viewModel = LivroFormularioViewModel(modo: .edicao(livroId: livro.id), repositorio: repositorio)
        await viewModel.carregar()
        viewModel.rascunho.estanteId = sala.id
        viewModel.rascunho.prateleira = "caixa azul"

        let salvou = await viewModel.salvar()

        XCTAssertTrue(salvou)
        let gravado = try XCTUnwrap(repositorio.livrosGuardados[livro.id])
        XCTAssertEqual(repositorio.livrosGuardados.count, 1)
        XCTAssertEqual(gravado.estanteId, sala.id)
        XCTAssertEqual(gravado.prateleira, "caixa azul")
        XCTAssertEqual(gravado.origem, .lexml)
        XCTAssertEqual(gravado.urn, livro.urn)
        XCTAssertEqual(gravado.itensSumario, livro.itensSumario)
    }

    func testEdicaoDeLivroQueSumiuViraErro() async {
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [escritorio])
        let viewModel = LivroFormularioViewModel(modo: .edicao(livroId: UUID()), repositorio: repositorio)

        await viewModel.carregar()

        XCTAssertEqual(viewModel.estado, .erro("O livro não existe mais."))
    }

    // MARK: Autores

    func testAdicionarEApagarAutores() {
        let viewModel = LivroFormularioViewModel(modo: .novo(estanteId: escritorio.id), repositorio: BibliotecaRepositorioEmMemoria())
        viewModel.rascunho.autores = ["A", "B", "C", "D"]

        viewModel.adicionarAutor()
        XCTAssertEqual(viewModel.rascunho.autores, ["A", "B", "C", "D", ""])

        viewModel.apagarAutores(em: IndexSet([1, 3]))
        XCTAssertEqual(viewModel.rascunho.autores, ["A", "C", ""])
    }

    /// Mesma convenção do `move(fromOffsets:toOffset:)` do SwiftUI, que o `onMove` usa.
    func testMoverAutores() {
        let casos: [(IndexSet, Int, [String])] = [
            (IndexSet([0]), 3, ["B", "C", "A", "D"]),
            (IndexSet([3]), 0, ["D", "A", "B", "C"]),
            (IndexSet([0]), 4, ["B", "C", "D", "A"]),
            (IndexSet([1]), 1, ["A", "B", "C", "D"]),
            (IndexSet([1]), 2, ["A", "B", "C", "D"]),
            (IndexSet([0, 2]), 4, ["B", "D", "A", "C"]),
        ]
        for (origem, destino, esperado) in casos {
            let viewModel = LivroFormularioViewModel(modo: .novo(estanteId: escritorio.id), repositorio: BibliotecaRepositorioEmMemoria())
            viewModel.rascunho.autores = ["A", "B", "C", "D"]
            viewModel.moverAutores(de: origem, para: destino)
            XCTAssertEqual(viewModel.rascunho.autores, esperado, "\(Array(origem)) → \(destino)")
        }
    }

    // MARK: Prateleira

    private func repositorioComPrateleiras() -> BibliotecaRepositorioEmMemoria {
        BibliotecaRepositorioEmMemoria(estantes: [escritorio, sala], livros: [
            Livro(estanteId: escritorio.id, titulo: "A", prateleira: "caixa azul"),
            Livro(estanteId: escritorio.id, titulo: "B", prateleira: "2ª de cima"),
            Livro(estanteId: sala.id, titulo: "C", prateleira: "aparador"),
        ])
    }

    func testCarregaAsPrateleirasDaEstanteDoRascunho() async {
        let viewModel = LivroFormularioViewModel(modo: .novo(estanteId: escritorio.id), repositorio: repositorioComPrateleiras())

        await viewModel.carregar()

        XCTAssertEqual(viewModel.prateleirasDaEstante, ["2ª de cima", "caixa azul"])
        XCTAssertEqual(viewModel.sugestoesDePrateleira, ["2ª de cima", "caixa azul"])
    }

    func testSugestoesSeguemOTextoDigitado() async {
        let viewModel = LivroFormularioViewModel(modo: .novo(estanteId: escritorio.id), repositorio: repositorioComPrateleiras())
        await viewModel.carregar()

        viewModel.rascunho.prateleira = "AZ"

        XCTAssertEqual(viewModel.sugestoesDePrateleira, ["caixa azul"])
    }

    func testTrocarDeEstanteRecarregaAsPrateleiras() async {
        let viewModel = LivroFormularioViewModel(modo: .novo(estanteId: escritorio.id), repositorio: repositorioComPrateleiras())
        await viewModel.carregar()

        viewModel.rascunho.estanteId = sala.id
        await viewModel.carregarPrateleiras()

        XCTAssertEqual(viewModel.prateleirasDaEstante, ["aparador"])
    }

    func testEscolherPrateleiraPreencheORascunho() async {
        let viewModel = LivroFormularioViewModel(modo: .novo(estanteId: escritorio.id), repositorio: repositorioComPrateleiras())
        await viewModel.carregar()
        viewModel.rascunho.prateleira = "cai"

        viewModel.escolherPrateleira("caixa azul")

        XCTAssertEqual(viewModel.rascunho.prateleira, "caixa azul")
        XCTAssertEqual(viewModel.sugestoesDePrateleira, [])
    }

    func testFalhaAoLerPrateleirasNaoAtrapalhaOFormulario() async {
        let repositorio = repositorioComPrateleiras()
        let viewModel = LivroFormularioViewModel(modo: .novo(estanteId: escritorio.id), repositorio: repositorio)
        await viewModel.carregar()

        repositorio.falharAoLer = true
        viewModel.rascunho.estanteId = sala.id
        await viewModel.carregarPrateleiras()

        XCTAssertEqual(viewModel.prateleirasDaEstante, [])
        XCTAssertEqual(viewModel.estado, .pronto)
        XCTAssertNil(viewModel.mensagemDeErro)
    }
}
