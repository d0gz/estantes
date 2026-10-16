import XCTest
@testable import Estantes

/// O `CategoriasViewModel` (tela de gerenciar) com o repositório falso: sem banco, sem tela.
@MainActor
final class CategoriasViewModelTests: XCTestCase {
    private let estante = Estante(nome: "Sala", criadaEm: Date(timeIntervalSinceReferenceDate: 1))
    private let civil = Categoria(nome: "Civil", cor: .laranja)
    private let penal = Categoria(nome: "Penal", cor: .amarelo)

    private func livro(_ categorias: Categoria...) -> Livro {
        Livro(estanteId: estante.id, titulo: "Livro", categoriaIds: Set(categorias.map(\.id)))
    }

    /// Civil em 1 livro, Penal em 2: cada resumo com a sua contagem (não trocadas entre categorias).
    func testCarregaAsCategoriasComAQuantidadeDeLivrosDeCada() async {
        let repositorio = BibliotecaRepositorioEmMemoria(
            estantes: [estante], livros: [livro(civil, penal), livro(penal)], categorias: [civil, penal]
        )
        let viewModel = CategoriasViewModel(repositorio: repositorio)

        await viewModel.carregar()

        XCTAssertEqual(viewModel.estado, .pronto([
            CategoriaResumo(categoria: civil, quantidadeDeLivros: 1),
            CategoriaResumo(categoria: penal, quantidadeDeLivros: 2),
        ]))
    }

    func testSemCategoriasFicaVazio() async {
        let viewModel = CategoriasViewModel(repositorio: BibliotecaRepositorioEmMemoria())
        await viewModel.carregar()
        XCTAssertEqual(viewModel.estado, .vazio)
    }

    func testFalhaAoLerViraEstadoDeErro() async {
        let repositorio = BibliotecaRepositorioEmMemoria(categorias: [civil])
        repositorio.falharAoLer = true
        let viewModel = CategoriasViewModel(repositorio: repositorio)

        await viewModel.carregar()

        XCTAssertEqual(viewModel.estado, .erro("Não foi possível carregar as categorias."))
    }

    // MARK: Apagar

    func testApagarTiraACategoriaDaListaEDosLivros() async {
        let comPenal = livro(civil, penal)
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [estante], livros: [comPenal], categorias: [civil, penal])
        let viewModel = CategoriasViewModel(repositorio: repositorio)
        await viewModel.carregar()

        await viewModel.apagar(penal)

        XCTAssertEqual(viewModel.estado, .pronto([CategoriaResumo(categoria: civil, quantidadeDeLivros: 1)]))
        XCTAssertEqual(repositorio.livrosGuardados[comPenal.id]?.categoriaIds, [civil.id])
    }

    /// No erro a lista continua na tela (relida do banco, onde nada mudou) e um alerta avisa.
    func testFalhaAoApagarAvisaEMantemALista() async {
        let repositorio = BibliotecaRepositorioEmMemoria(categorias: [civil, penal])
        let viewModel = CategoriasViewModel(repositorio: repositorio)
        await viewModel.carregar()
        repositorio.falharAoGravar = true

        await viewModel.apagar(penal)

        XCTAssertEqual(viewModel.mensagemDeErro, "Não foi possível apagar a categoria.")
        XCTAssertEqual(viewModel.estado, .pronto([
            CategoriaResumo(categoria: civil, quantidadeDeLivros: 0),
            CategoriaResumo(categoria: penal, quantidadeDeLivros: 0),
        ]))
    }

    /// A confirmação usa a contagem de agora, não a da lista: um livro marcado depois do `carregar` conta.
    func testPedidoDeExclusaoReleAQuantidadeDeLivros() async {
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [estante], categorias: [penal])
        let viewModel = CategoriasViewModel(repositorio: repositorio)
        await viewModel.carregar()
        let marcadoDepois = livro(penal)
        repositorio.livrosGuardados[marcadoDepois.id] = marcadoDepois

        let pedido = await viewModel.pedidoDeExclusao(de: penal)

        XCTAssertEqual(pedido, ExclusaoDeCategoria(categoria: penal, quantidadeDeLivros: 1))
    }
}
