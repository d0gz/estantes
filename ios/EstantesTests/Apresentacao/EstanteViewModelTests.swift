import XCTest
@testable import Estantes

@MainActor
final class EstanteViewModelTests: XCTestCase {
    private let sala = Estante(nome: "Sala")
    private let escritorio = Estante(nome: "Escritório")

    /// Cada livro com as suas, em ordem alfabética (Processo foi marcada antes de Civil, e Filosofia é do outro livro).
    func testCategoriasDeCadaLivroEmOrdemAlfabetica() async {
        let civil = Categoria(nome: "Civil", cor: .laranja)
        let processo = Categoria(nome: "Processo", cor: .verde)
        let filosofia = Categoria(nome: "Filosofia", cor: .marrom)
        let comDuas = Livro(estanteId: sala.id, titulo: "Com duas", categoriaIds: [processo.id, civil.id])
        let comUma = Livro(estanteId: sala.id, titulo: "Com uma", categoriaIds: [filosofia.id])
        let semNenhuma = Livro(estanteId: sala.id, titulo: "Sem nenhuma")
        let repositorio = BibliotecaRepositorioEmMemoria(
            estantes: [sala], livros: [comDuas, comUma, semNenhuma], categorias: [civil, processo, filosofia]
        )
        let viewModel = EstanteViewModel(estante: sala, repositorio: repositorio)

        await viewModel.carregar()

        XCTAssertEqual(viewModel.categorias(de: comDuas), [civil, processo])
        XCTAssertEqual(viewModel.categorias(de: comUma), [filosofia])
        XCTAssertEqual(viewModel.categorias(de: semNenhuma), [])
    }

    /// Depois que a folha de escolha grava, a releitura mostra as novas (a linha não fica velha).
    func testRecarregarMostraAsCategoriasGravadas() async {
        let civil = Categoria(nome: "Civil", cor: .laranja)
        var livro = Livro(estanteId: sala.id, titulo: "Livro")
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [sala], livros: [livro], categorias: [civil])
        let viewModel = EstanteViewModel(estante: sala, repositorio: repositorio)
        await viewModel.carregar()
        livro.categoriaIds = [civil.id]
        repositorio.livrosGuardados[livro.id] = livro

        await viewModel.carregar()

        // O livro da tela, relido do repositório (e não a struct alterada aqui no teste).
        guard case .pronta(let grupos) = viewModel.estado, let naTela = grupos.first?.livros.first else {
            return XCTFail("Esperava a lista, veio \(viewModel.estado)")
        }
        XCTAssertEqual(viewModel.categorias(de: naTela), [civil])
    }

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

    func testCabecalhoDaPrateleiraComContagem() {
        let livro = Livro(estanteId: sala.id, titulo: "A")
        let caixa = GrupoDePrateleira(prateleira: "Caixa azul", livros: [livro, livro])
        let semPrateleira = GrupoDePrateleira(prateleira: nil, livros: [livro])

        XCTAssertEqual(EstanteViewModel.cabecalho(caixa), "Caixa azul · 2")
        XCTAssertEqual(EstanteViewModel.cabecalho(semPrateleira), "Sem prateleira · 1")
    }
}
