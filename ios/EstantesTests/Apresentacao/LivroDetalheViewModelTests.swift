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

    /// Só as do livro (Filosofia existe mas fica de fora), na ordem alfabética do repositório.
    func testCategoriasDoLivroSaoSoAsDeleEmOrdemAlfabetica() async {
        let processo = Categoria(nome: "Processo", cor: .verde)
        let civil = Categoria(nome: "Civil", cor: .laranja)
        let filosofia = Categoria(nome: "Filosofia", cor: .marrom)
        var livro = livroCompleto()
        livro.categoriaIds = [processo.id, civil.id]
        let viewModel = LivroDetalheViewModel(
            livroId: livro.id,
            repositorio: BibliotecaRepositorioEmMemoria(estantes: [sala], livros: [livro], categorias: [processo, civil, filosofia])
        )

        await viewModel.carregar()

        XCTAssertEqual(viewModel.categoriasDoLivro, [civil, processo])
    }

    func testLivroSemCategoriaNaoTemChips() async {
        let livro = livroCompleto()
        let viewModel = LivroDetalheViewModel(
            livroId: livro.id,
            repositorio: BibliotecaRepositorioEmMemoria(estantes: [sala], livros: [livro], categorias: [Categoria(nome: "Civil", cor: .laranja)])
        )

        await viewModel.carregar()

        XCTAssertEqual(viewModel.categoriasDoLivro, [])
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

    // MARK: Cabeçalho

    func testCabecalhoComTituloVolumeEAutor() {
        // O subtítulo só de espaços some; o volume mostra o rótulo impresso.
        XCTAssertEqual(LivroDetalheViewModel.cabecalho(de: livroCompleto()), CabecalhoDoLivro(
            titulo: "Tratado de direito privado", subtitulo: nil, volume: "Tomo XLVIII", autores: "Miranda, Pontes de"
        ))
    }

    // Vários autores: só os sobrenomes, como na ABNT (NBR 6023): até 3 todos; de 4 em diante, o primeiro e "et al.".

    func testCabecalhoComDoisAutoresSoOsSobrenomes() {
        XCTAssertEqual(linhaDosAutores(["Mendes, Gilmar Ferreira", "Branco, Paulo Gustavo Gonet"]), "Mendes e Branco")
    }

    func testCabecalhoComTresAutoresIgnoraOVazio() {
        XCTAssertEqual(
            linhaDosAutores(["Cintra, Antonio Carlos de Araújo", " ", "Grinover, Ada Pellegrini", "Dinamarco, Cândido Rangel"]),
            "Cintra, Grinover e Dinamarco"
        )
    }

    func testCabecalhoComQuatroAutoresUsaEtAl() {
        XCTAssertEqual(
            linhaDosAutores(["Sarlet, Ingo Wolfgang", "Marinoni, Luiz Guilherme", "Mitidiero, Daniel", "Arenhart, Sérgio Cruz"]),
            "Sarlet et al."
        )
    }

    /// Sem vírgula não há como saber o sobrenome: o nome vai inteiro.
    func testCabecalhoComNomeSemVirgulaUsaONomeInteiro() {
        XCTAssertEqual(linhaDosAutores(["Pontes de Miranda", "Kelsen, Hans"]), "Pontes de Miranda e Kelsen")
        XCTAssertEqual(linhaDosAutores(["Kelsen, Hans", "Pontes de Miranda", "Reale, Miguel"]), "Kelsen, Pontes de Miranda e Reale")
        XCTAssertEqual(linhaDosAutores(["Pontes de Miranda", "A, B", "C, D", "E, F"]), "Pontes de Miranda et al.")
    }

    func testCabecalhoSubtitulo() {
        XCTAssertEqual(
            LivroDetalheViewModel.cabecalho(de: Livro(estanteId: sala.id, titulo: "A", subtitulo: " Parte geral ")).subtitulo,
            "Parte geral"
        )
    }

    func testCabecalhoSemAutor() {
        XCTAssertNil(linhaDosAutores([]))
        XCTAssertNil(linhaDosAutores([" "]))
    }

    private func linhaDosAutores(_ autores: [String]) -> String? {
        LivroDetalheViewModel.cabecalho(de: Livro(estanteId: sala.id, titulo: "A", autores: autores)).autores
    }

    // MARK: Campos mostrados

    func testGruposSoComCamposPreenchidos() {
        let grupos = LivroDetalheViewModel.grupos(de: livroCompleto())

        // Subtítulo e volume ficam só no cabeçalho; os autores, no primeiro cartão, sem rótulo por linha.
        XCTAssertEqual(grupos.map(\.titulo), ["Autor", "Obra", "Publicação", "Na estante"])
        XCTAssertEqual(grupos[0].campos, [CampoDoLivro(rotulo: nil, valor: "Miranda, Pontes de")])
        // O cabeçalho mostra o rótulo ("Tomo XLVIII"); o número aparece aqui, para não sumir.
        XCTAssertEqual(grupos[1].campos, [
            CampoDoLivro(rotulo: "Parte", valor: "Parte especial"),
            CampoDoLivro(rotulo: "Número do volume", valor: "48"),
            CampoDoLivro(rotulo: "Artigos", valor: "Arts. 1710–1779"),
        ])
        // Edição, páginas e ISBN vazios não aparecem; o ano sem ponto de milhar.
        XCTAssertEqual(grupos[2].campos, [
            CampoDoLivro(rotulo: "Editora", valor: "Borsoi"),
            CampoDoLivro(rotulo: "Local", valor: "Rio de Janeiro"),
            CampoDoLivro(rotulo: "Ano", valor: "1965"),
        ])
        XCTAssertEqual(grupos[3].campos, [
            CampoDoLivro(rotulo: "Prateleira", valor: "caixa azul"),
            CampoDoLivro(rotulo: "Origem", valor: "LexML"),
        ])
    }

    func testLivroSoComTituloMostraSoAOrigem() {
        let grupos = LivroDetalheViewModel.grupos(de: Livro(estanteId: sala.id, titulo: "A"))
        XCTAssertEqual(grupos, [
            GrupoDeCampos(titulo: "Na estante", campos: [CampoDoLivro(rotulo: "Origem", valor: "Cadastro manual")]),
        ])
    }

    func testVariosAutoresUmPorLinhaNaOrdem() {
        let livro = Livro(estanteId: sala.id, titulo: "A", autores: ["Um", "  ", "Dois"])
        XCTAssertEqual(LivroDetalheViewModel.grupos(de: livro).first, GrupoDeCampos(titulo: "Autores", campos: [
            CampoDoLivro(rotulo: nil, valor: "Um"),
            CampoDoLivro(rotulo: nil, valor: "Dois"),
        ]))
    }

    func testVolumeSoComNumeroFicaSoNoCabecalho() {
        let livro = Livro(estanteId: sala.id, titulo: "A", volume: 3)
        XCTAssertEqual(LivroDetalheViewModel.cabecalho(de: livro).volume, "Vol. 3")
        XCTAssertFalse(LivroDetalheViewModel.grupos(de: livro).contains { $0.titulo == "Obra" })
    }

    func testRotuloSemNumeroNaoGeraALinhaDoNumero() {
        let livro = Livro(estanteId: sala.id, titulo: "A", volumeRotulo: "Tomo II")
        XCTAssertEqual(LivroDetalheViewModel.cabecalho(de: livro).volume, "Tomo II")
        XCTAssertFalse(LivroDetalheViewModel.grupos(de: livro).contains { $0.titulo == "Obra" })
    }

    func testRotuloSoDeEspacosValeComoSemRotulo() {
        let livro = Livro(estanteId: sala.id, titulo: "A", volume: 48, volumeRotulo: "  ")
        XCTAssertEqual(LivroDetalheViewModel.cabecalho(de: livro).volume, "Vol. 48")
        XCTAssertFalse(LivroDetalheViewModel.grupos(de: livro).contains { $0.titulo == "Obra" })
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
