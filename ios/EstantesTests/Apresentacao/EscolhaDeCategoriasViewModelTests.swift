import XCTest
@testable import Estantes

/// A folha de escolher as categorias de um livro, com o repositório falso.
@MainActor
final class EscolhaDeCategoriasViewModelTests: XCTestCase {
    private let estante = Estante(nome: "Sala", criadaEm: Date(timeIntervalSinceReferenceDate: 1))
    private let civil = Categoria(nome: "Civil", cor: .laranja)
    private let penal = Categoria(nome: "Penal", cor: .amarelo)
    private let trabalho = Categoria(nome: "Trabalho", cor: .indigo)

    private func livro(_ categorias: Categoria...) -> Livro {
        Livro(estanteId: estante.id, titulo: "Curso de direito civil", autores: ["Diniz, Maria Helena"],
              prateleira: "2ª de cima", categoriaIds: Set(categorias.map(\.id)))
    }

    private func montar(_ livro: Livro, categorias: [Categoria]) -> (EscolhaDeCategoriasViewModel, BibliotecaRepositorioEmMemoria) {
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [estante], livros: [livro], categorias: categorias)
        return (EscolhaDeCategoriasViewModel(livroId: livro.id, repositorio: repositorio), repositorio)
    }

    func testCarregaTodasAsCategoriasComAsDoLivroMarcadas() async {
        let (viewModel, _) = montar(livro(civil), categorias: [civil, trabalho])

        await viewModel.carregar()

        XCTAssertEqual(viewModel.estado, .pronto([civil, trabalho]))
        XCTAssertEqual(viewModel.marcadas, [civil.id])
    }

    func testAlternarDuasVezesVoltaAoQueEra() async {
        let (viewModel, _) = montar(livro(civil), categorias: [civil, trabalho])
        await viewModel.carregar()

        viewModel.alternar(trabalho)
        XCTAssertEqual(viewModel.marcadas, [civil.id, trabalho.id])
        viewModel.alternar(trabalho)

        XCTAssertEqual(viewModel.marcadas, [civil.id])
    }

    /// Só as categorias mudam: título, autores e prateleira continuam os do livro.
    func testSalvarGravaAsMarcadasEPreservaORestoDoLivro() async {
        let original = livro(civil)
        let (viewModel, repositorio) = montar(original, categorias: [civil, trabalho])
        await viewModel.carregar()
        viewModel.alternar(civil)
        viewModel.alternar(trabalho)

        let salvou = await viewModel.salvar()

        var esperado = original
        esperado.categoriaIds = [trabalho.id]
        XCTAssertTrue(salvou)
        XCTAssertEqual(repositorio.livrosGuardados[original.id], esperado)
    }

    /// A criada pela "Nova categoria" entra na ordem alfabética e já marcada.
    func testNovaCategoriaEntraEmOrdemEJaMarcada() async {
        let (viewModel, _) = montar(livro(), categorias: [civil, trabalho])
        await viewModel.carregar()

        viewModel.incluirNova(penal)

        XCTAssertEqual(viewModel.estado, .pronto([civil, penal, trabalho]))
        XCTAssertEqual(viewModel.marcadas, [penal.id])
    }

    func testFalhaAoSalvarAvisaEMantemAEscolha() async {
        let (viewModel, repositorio) = montar(livro(), categorias: [civil])
        await viewModel.carregar()
        viewModel.alternar(civil)
        repositorio.falharAoGravar = true

        let salvou = await viewModel.salvar()

        XCTAssertFalse(salvou)
        XCTAssertEqual(viewModel.mensagemDeErro, "Não foi possível salvar as categorias.")
        XCTAssertEqual(viewModel.marcadas, [civil.id])
    }

    func testLivroApagadoFicaNaoEncontrado() async {
        let repositorio = BibliotecaRepositorioEmMemoria(categorias: [civil])
        let viewModel = EscolhaDeCategoriasViewModel(livroId: UUID(), repositorio: repositorio)

        await viewModel.carregar()

        XCTAssertEqual(viewModel.estado, .naoEncontrado)
    }
}
