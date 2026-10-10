import XCTest
@testable import Estantes

@MainActor
final class EstanteViewModelTests: XCTestCase {
    private let sala = Estante(nome: "Sala")
    private let escritorio = Estante(nome: "Escritório")

    func testCarregaSoOsLivrosDaEstanteAgrupados() async {
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [sala, escritorio], livros: [
            Livro(estanteId: sala.id, titulo: "B", prateleira: "1ª"),
            Livro(estanteId: sala.id, titulo: "A"),
            Livro(estanteId: escritorio.id, titulo: "C", prateleira: "1ª"),
        ])
        let viewModel = EstanteViewModel(estante: sala, repositorio: repositorio)

        await viewModel.carregar()

        guard case .pronta(let grupos) = viewModel.estado else {
            return XCTFail("Esperava a lista, veio \(viewModel.estado)")
        }
        XCTAssertEqual(grupos.map(\.prateleira), ["1ª", nil])
        XCTAssertEqual(grupos.map { $0.livros.map(\.titulo) }, [["B"], ["A"]])
    }

    func testEstanteSemLivrosFicaVazia() async {
        let viewModel = EstanteViewModel(estante: sala, repositorio: BibliotecaRepositorioEmMemoria(estantes: [sala]))
        await viewModel.carregar()
        XCTAssertEqual(viewModel.estado, .vazia)
    }

    func testFalhaAoLerViraErro() async {
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [sala])
        repositorio.falharAoLer = true
        let viewModel = EstanteViewModel(estante: sala, repositorio: repositorio)

        await viewModel.carregar()

        XCTAssertEqual(viewModel.estado, .erro("Não foi possível carregar os livros."))
    }

    func testRecarregarMostraOQueMudouNoBanco() async {
        let livro = Livro(estanteId: sala.id, titulo: "A")
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [sala], livros: [livro])
        let viewModel = EstanteViewModel(estante: sala, repositorio: repositorio)
        await viewModel.carregar()

        repositorio.livrosGuardados[livro.id] = nil
        await viewModel.carregar()

        XCTAssertEqual(viewModel.estado, .vazia)
    }

    func testLinhaSecundariaComAutoresEAno() {
        let livro = Livro(estanteId: sala.id, titulo: "A", autores: ["Silva, José Afonso da", "Outro, Autor"], ano: 2014)
        XCTAssertEqual(EstanteViewModel.linhaSecundaria(livro), "Silva, José Afonso da; Outro, Autor · 2014")
        XCTAssertEqual(EstanteViewModel.linhaSecundaria(Livro(estanteId: sala.id, titulo: "A", ano: 1998)), "1998")
        XCTAssertNil(EstanteViewModel.linhaSecundaria(Livro(estanteId: sala.id, titulo: "A")))
    }
}
