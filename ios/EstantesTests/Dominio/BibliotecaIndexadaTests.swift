import XCTest
@testable import Estantes

/// A `BibliotecaIndexada` repassa cada chamada ao repositório e mantém o índice da busca em dia.
/// Cada teste grava pelo decorador e confere a busca depois: um caminho de gravação esquecido
/// deixaria o índice com o livro velho (ou sem o novo).
@MainActor
final class BibliotecaIndexadaTests: XCTestCase {
    private let escritorio = Estante(nome: "Escritório")
    private lazy var lassalle = Livro(
        estanteId: escritorio.id, titulo: "A essência da constituição", autores: ["Lassalle, Ferdinand"]
    )
    private lazy var base = BibliotecaRepositorioEmMemoria(estantes: [escritorio], livros: [lassalle])
    private lazy var biblioteca = BibliotecaIndexada(base: base)

    private func ids(_ texto: String, filtro: FiltroBusca = FiltroBusca()) async throws -> [UUID] {
        try await biblioteca.buscar(texto, filtro: filtro).resultados.map { $0.livro.id }
    }

    func testPrepararIndexaOsLivrosQueJaEstavamNoBanco() async throws {
        try await biblioteca.preparar()

        let achados = try await ids("lassalle")
        XCTAssertEqual(achados, [lassalle.id])
    }

    // MARK: - Livros

    func testLivroNovoSalvoApareceNaBusca() async throws {
        try await biblioteca.preparar()
        let pontes = Livro(estanteId: escritorio.id, titulo: "Tratado de direito privado", autores: ["Pontes de Miranda"])

        try await biblioteca.salvar(pontes)

        let achados = try await ids("tratado")
        XCTAssertEqual(achados, [pontes.id])
    }

    func testLivroEditadoEAchadoPeloTituloNovoENaoPeloAntigo() async throws {
        try await biblioteca.preparar()
        var editado = lassalle
        editado.titulo = "Sobre o poder constituinte"

        try await biblioteca.salvar(editado)

        let pelaPalavraNova = try await ids("poder")
        let pelaPalavraAntiga = try await ids("essencia")
        XCTAssertEqual(pelaPalavraNova, [lassalle.id])
        XCTAssertEqual(pelaPalavraAntiga, [])
    }

    func testLivroApagadoSaiDaBusca() async throws {
        try await biblioteca.preparar()

        try await biblioteca.apagarLivro(id: lassalle.id)

        let achados = try await ids("lassalle")
        XCTAssertEqual(achados, [])
    }

    // MARK: - Estantes

    func testEstanteApagadaSemDestinoTiraOsLivrosDelaDaBusca() async throws {
        try await biblioteca.preparar()

        try await biblioteca.apagarEstante(id: escritorio.id, moverLivrosPara: nil)

        let achados = try await ids("lassalle")
        XCTAssertEqual(achados, [])
    }

    func testEstanteApagadaComDestinoLevaOsLivrosParaOFiltroDaEstanteNova() async throws {
        let sala = Estante(nome: "Sala")
        try await base.salvar(sala)
        try await biblioteca.preparar()

        try await biblioteca.apagarEstante(id: escritorio.id, moverLivrosPara: sala.id)

        let naSala = try await ids("lassalle", filtro: FiltroBusca(estanteIds: [sala.id]))
        XCTAssertEqual(naSala, [lassalle.id])
    }

    // MARK: - Categorias

    func testCategoriaRenomeadaEAchadaPeloNomeNovoENaoPeloAntigo() async throws {
        var categoria = Categoria(nome: "Constitucional", cor: .verde)
        try await base.salvar(categoria)
        lassalle.categoriaIds = [categoria.id]
        try await base.salvar(lassalle)
        try await biblioteca.preparar()

        categoria.nome = "Teoria do Estado"
        try await biblioteca.salvar(categoria)

        let peloNomeNovo = try await ids("teoria")
        let peloNomeAntigo = try await ids("constitucional")
        XCTAssertEqual(peloNomeNovo, [lassalle.id])
        XCTAssertEqual(peloNomeAntigo, [])
    }

    func testCategoriaApagadaDeixaDeAcharOLivroPeloNomeEPeloFiltro() async throws {
        let categoria = Categoria(nome: "Constitucional", cor: .verde)
        try await base.salvar(categoria)
        lassalle.categoriaIds = [categoria.id]
        try await base.salvar(lassalle)
        try await biblioteca.preparar()

        try await biblioteca.apagarCategoria(id: categoria.id)

        let peloNome = try await ids("constitucional")
        let peloFiltro = try await ids("", filtro: FiltroBusca(categoriaIds: [categoria.id]))
        XCTAssertEqual(peloNome, [])
        XCTAssertEqual(peloFiltro, [])
    }

    // A gravação da categoria deu certo e só a releitura da lista falhou: não vira erro, e o índice velho
    // (com o nome antigo) não pode continuar. A busca seguinte monta tudo de novo.
    func testReleituraDeCategoriasQueFalhaDescartaOIndice() async throws {
        var categoria = Categoria(nome: "Constitucional", cor: .verde)
        try await base.salvar(categoria)
        lassalle.categoriaIds = [categoria.id]
        try await base.salvar(lassalle)
        try await biblioteca.preparar()

        categoria.nome = "Teoria do Estado"
        base.falharAoLer = true
        try await biblioteca.salvar(categoria)
        base.falharAoLer = false

        let peloNomeNovo = try await ids("teoria")
        XCTAssertEqual(peloNomeNovo, [lassalle.id])
    }

    // MARK: - Falhas e ordem

    func testGravacaoQueFalhaLancaOErroENaoMudaOIndice() async throws {
        try await biblioteca.preparar()
        base.falharAoGravar = true

        do {
            try await biblioteca.apagarLivro(id: lassalle.id)
            XCTFail("A falha da gravação deveria chegar a quem chamou.")
        } catch is BibliotecaRepositorioEmMemoria.FalhaSimulada {}

        let achados = try await ids("lassalle")
        XCTAssertEqual(achados, [lassalle.id])
    }

    func testLivroSalvoAntesDePrepararEntraNaMontagem() async throws {
        let pontes = Livro(estanteId: escritorio.id, titulo: "Tratado de direito privado", autores: ["Pontes de Miranda"])

        try await biblioteca.salvar(pontes)

        let achados = try await ids("tratado")
        XCTAssertEqual(achados, [pontes.id])
    }

    func testLeituraQueFalhaAoPrepararLancaOErroEATentativaSeguinteMonta() async throws {
        base.falharAoLer = true
        do {
            _ = try await biblioteca.buscar("lassalle")
            XCTFail("A falha da leitura deveria chegar a quem buscou.")
        } catch is BibliotecaRepositorioEmMemoria.FalhaSimulada {}

        base.falharAoLer = false

        let achados = try await ids("lassalle")
        XCTAssertEqual(achados, [lassalle.id])
    }
}
