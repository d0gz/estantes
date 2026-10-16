import XCTest
@testable import Estantes

/// A folha de criar/editar categoria com o repositório falso. As regras do nome (`NomeDeCategoria`) e da cor
/// (`CorSugerida`) já têm testes próprios; aqui se confere a ligação delas com a tela e a gravação.
@MainActor
final class CategoriaFormularioViewModelTests: XCTestCase {
    private let tributario = Categoria(nome: "Tributário", cor: .vermelho)

    /// Com uma vermelha existente, a menos usada é a laranja (primeira com 0 usos na paleta).
    func testNovaComecaComACorSugerida() async {
        let viewModel = CategoriaFormularioViewModel(
            modo: .nova, repositorio: BibliotecaRepositorioEmMemoria(categorias: [tributario])
        )

        await viewModel.carregar()

        XCTAssertEqual(viewModel.cor, .laranja)
        XCTAssertEqual(viewModel.nome, "")
    }

    /// Na edição a cor é a da categoria, não a sugerida (aqui seria a laranja).
    func testEdicaoComecaComONomeEACorDaCategoria() async {
        let viewModel = CategoriaFormularioViewModel(
            modo: .edicao(tributario), repositorio: BibliotecaRepositorioEmMemoria(categorias: [tributario])
        )

        await viewModel.carregar()

        XCTAssertEqual(viewModel.nome, "Tributário")
        XCTAssertEqual(viewModel.cor, .vermelho)
    }

    // MARK: Salvar

    func testNomeSoComEspacosNaoGravaEOErroSoApareceDepoisDeTentar() async {
        let repositorio = BibliotecaRepositorioEmMemoria()
        let viewModel = CategoriaFormularioViewModel(modo: .nova, repositorio: repositorio)
        await viewModel.carregar()
        viewModel.nome = "   "
        XCTAssertNil(viewModel.problemaDoNome)

        let salva = await viewModel.salvar()

        XCTAssertNil(salva)
        XCTAssertEqual(viewModel.problemaDoNome, "Dê um nome à categoria.")
        XCTAssertTrue(repositorio.categoriasGuardadas.isEmpty)
    }

    /// "tributario" repete "Tributário" sem diferenciar acento e maiúsculas; o erro cita o nome que já existe.
    func testNomeRepetidoNaoGravaECitaACategoriaExistente() async {
        let repositorio = BibliotecaRepositorioEmMemoria(categorias: [tributario])
        let viewModel = CategoriaFormularioViewModel(modo: .nova, repositorio: repositorio)
        await viewModel.carregar()
        viewModel.nome = "tributario"

        let salva = await viewModel.salvar()

        XCTAssertNil(salva)
        XCTAssertEqual(viewModel.problemaDoNome, "Já existe a categoria \"Tributário\".")
        XCTAssertEqual(repositorio.categoriasGuardadas.count, 1)
    }

    /// Manter o próprio nome não é repetição; a edição grava sobre a mesma categoria (mesmo id), sem duplicar.
    func testEdicaoMantendoONomeTrocaACorNaMesmaCategoria() async {
        let repositorio = BibliotecaRepositorioEmMemoria(categorias: [tributario])
        let viewModel = CategoriaFormularioViewModel(modo: .edicao(tributario), repositorio: repositorio)
        await viewModel.carregar()
        viewModel.cor = .menta

        let salva = await viewModel.salvar()

        let esperada = Categoria(id: tributario.id, nome: "Tributário", cor: .menta)
        XCTAssertEqual(salva, esperada)
        XCTAssertEqual(Array(repositorio.categoriasGuardadas.values), [esperada])
    }

    func testNovaGravaComONomeAparado() async {
        let repositorio = BibliotecaRepositorioEmMemoria()
        let viewModel = CategoriaFormularioViewModel(modo: .nova, repositorio: repositorio)
        await viewModel.carregar()
        viewModel.nome = "  Penal  "

        let salva = await viewModel.salvar()

        XCTAssertEqual(salva?.nome, "Penal")
        XCTAssertEqual(repositorio.categoriasGuardadas.values.map(\.nome), ["Penal"])
    }

    /// A folha continua aberta (sem categoria devolvida) com o que foi digitado, e um alerta avisa.
    func testFalhaAoGravarAvisaENaoDevolveCategoria() async {
        let repositorio = BibliotecaRepositorioEmMemoria()
        let viewModel = CategoriaFormularioViewModel(modo: .nova, repositorio: repositorio)
        await viewModel.carregar()
        viewModel.nome = "Penal"
        repositorio.falharAoGravar = true

        let salva = await viewModel.salvar()

        XCTAssertNil(salva)
        XCTAssertEqual(viewModel.mensagemDeErro, "Não foi possível salvar a categoria.")
        XCTAssertEqual(viewModel.nome, "Penal")
    }
}
