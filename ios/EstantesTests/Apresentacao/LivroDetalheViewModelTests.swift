import XCTest
@testable import Estantes

@MainActor
final class LivroDetalheViewModelTests: XCTestCase {
    private let sala = Estante(nome: "Sala")

    private func livroCompleto() -> Livro {
        Livro(
            estanteId: sala.id, titulo: "Tratado de direito privado", subtitulo: "  ",
            autores: ["Miranda, Pontes de"], editora: "Borsoi", local: "Rio de Janeiro",
            volume: 48, volumeRotulo: "Tomo XLVIII", parte: "Parte especial",
            artigosInicio: 1710, artigosFim: 1779, ano: 1965, origem: .lexml, prateleira: "caixa azul"
        )
    }

    func testCarregaOLivro() async {
        let livro = livroCompleto()
        let viewModel = LivroDetalheViewModel(
            livroId: livro.id, repositorio: BibliotecaRepositorioEmMemoria(estantes: [sala], livros: [livro])
        )

        await viewModel.carregar()

        XCTAssertEqual(viewModel.estado, .pronto(livro))
    }

    func testIdInexistenteFicaNaoEncontrado() async {
        let viewModel = LivroDetalheViewModel(livroId: UUID(), repositorio: BibliotecaRepositorioEmMemoria())
        await viewModel.carregar()
        XCTAssertEqual(viewModel.estado, .naoEncontrado)
    }

    func testFalhaAoLerViraErro() async {
        let repositorio = BibliotecaRepositorioEmMemoria()
        repositorio.falharAoLer = true
        let viewModel = LivroDetalheViewModel(livroId: UUID(), repositorio: repositorio)

        await viewModel.carregar()

        XCTAssertEqual(viewModel.estado, .erro("Não foi possível carregar o livro."))
    }

    func testApagarRemoveOLivroEDevolveVerdadeiro() async {
        let livro = livroCompleto()
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [sala], livros: [livro])
        let viewModel = LivroDetalheViewModel(livroId: livro.id, repositorio: repositorio)

        let apagou = await viewModel.apagar()

        XCTAssertTrue(apagou)
        XCTAssertNil(repositorio.livrosGuardados[livro.id])
    }

    func testFalhaAoApagarMostraMensagemENaoVolta() async {
        let livro = livroCompleto()
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [sala], livros: [livro])
        repositorio.falharAoGravar = true
        let viewModel = LivroDetalheViewModel(livroId: livro.id, repositorio: repositorio)

        let apagou = await viewModel.apagar()

        XCTAssertFalse(apagou)
        XCTAssertEqual(viewModel.mensagemDeErro, "Não foi possível apagar o livro.")
        XCTAssertNotNil(repositorio.livrosGuardados[livro.id])
    }

    // MARK: Campos mostrados

    func testSecoesSoComCamposPreenchidos() {
        let secoes = LivroDetalheViewModel.secoes(de: livroCompleto())

        XCTAssertEqual(secoes.map(\.titulo), ["Obra", "Autoria", "Publicação", "Na estante"])
        // O subtítulo só de espaços some; o volume mostra o rótulo impresso.
        XCTAssertEqual(secoes[0].campos, [
            CampoDoLivro(rotulo: "Parte", valor: "Parte especial"),
            CampoDoLivro(rotulo: "Volume", valor: "Tomo XLVIII"),
            CampoDoLivro(rotulo: "Artigos", valor: "Arts. 1710–1779"),
        ])
        XCTAssertEqual(secoes[1].campos, [CampoDoLivro(rotulo: "Autor", valor: "Miranda, Pontes de")])
        XCTAssertEqual(secoes[3].campos, [
            CampoDoLivro(rotulo: "Prateleira", valor: "caixa azul"),
            CampoDoLivro(rotulo: "Origem", valor: "LexML"),
        ])
    }

    func testLivroSoComTituloMostraSoAOrigem() {
        let secoes = LivroDetalheViewModel.secoes(de: Livro(estanteId: sala.id, titulo: "A"))
        XCTAssertEqual(secoes, [
            SecaoDoLivro(titulo: "Na estante", campos: [CampoDoLivro(rotulo: "Origem", valor: "Cadastro manual")]),
        ])
    }

    func testVariosAutoresUmPorLinha() {
        let livro = Livro(estanteId: sala.id, titulo: "A", autores: ["Um", "Dois"])
        XCTAssertEqual(
            LivroDetalheViewModel.secoes(de: livro).first?.campos,
            [CampoDoLivro(rotulo: "Autores", valor: "Um\nDois")]
        )
    }

    func testVolumeSemRotuloUsaONumero() {
        XCTAssertEqual(LivroDetalheViewModel.textoDoVolume(Livro(estanteId: sala.id, titulo: "A", volume: 3)), "Vol. 3")
        XCTAssertNil(LivroDetalheViewModel.textoDoVolume(Livro(estanteId: sala.id, titulo: "A")))
    }

    func testTextoDosArtigos() {
        XCTAssertEqual(LivroDetalheViewModel.textoDosArtigos(inicio: 1710, fim: 1779), "Arts. 1710–1779")
        XCTAssertEqual(LivroDetalheViewModel.textoDosArtigos(inicio: 5, fim: 5), "Art. 5")
        XCTAssertEqual(LivroDetalheViewModel.textoDosArtigos(inicio: 1710, fim: nil), "A partir do art. 1710")
        XCTAssertEqual(LivroDetalheViewModel.textoDosArtigos(inicio: nil, fim: 1779), "Até o art. 1779")
        XCTAssertNil(LivroDetalheViewModel.textoDosArtigos(inicio: nil, fim: nil))
    }
}
