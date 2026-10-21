import XCTest
@testable import Estantes

/// O `ExportacaoViewModel` com o repositório falso e o formato v1 de verdade, num diretório temporário próprio.
@MainActor
final class ExportacaoViewModelTests: XCTestCase {
    private let escritorio = Estante(nome: "Escritório", criadaEm: Date(timeIntervalSince1970: 1_790_845_200))
    private let civil = Categoria(nome: "Civil", cor: .laranja)
    private var repositorio: BibliotecaRepositorioEmMemoria!
    private var pasta: URL!

    override func setUpWithError() throws {
        repositorio = BibliotecaRepositorioEmMemoria(estantes: [escritorio])
        pasta = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: pasta)
    }

    private func fazerViewModel(carregarExemplos: (() async throws -> Void)? = nil) -> ExportacaoViewModel {
        let codificador = BibliotecaExportadaV1()
        return ExportacaoViewModel(
            exportar: ExportarBiblioteca(repositorio: repositorio, codificador: codificador),
            importar: ImportarBiblioteca(repositorio: repositorio, codificador: codificador),
            carregarExemplos: carregarExemplos,
            // 21/10/2026, 15h UTC: o mesmo dia em qualquer fuso do Brasil.
            hoje: { Date(timeIntervalSince1970: 1_792_594_800) },
            pasta: pasta
        )
    }

    /// Um arquivo de backup com 2 livros, 1 estante e 1 categoria, gravado na pasta do teste.
    private func arquivoDeBackup() throws -> URL {
        let conteudo = ConteudoDaBiblioteca(
            estantes: [escritorio], categorias: [civil],
            livros: [Livro(estanteId: escritorio.id, titulo: "Um", categoriaIds: [civil.id]),
                     Livro(estanteId: escritorio.id, titulo: "Dois")]
        )
        return try gravar(BibliotecaExportadaV1().codificar(conteudo), como: "backup.json")
    }

    private func gravar(_ dados: Data, como nome: String) throws -> URL {
        let url = pasta.appendingPathComponent(nome)
        try dados.write(to: url)
        return url
    }

    // MARK: Exportar

    func testExportarGravaOArquivoComADataNoNomeEAbreACompartilhar() async throws {
        let viewModel = fazerViewModel()

        await viewModel.exportarBiblioteca()

        let url = try XCTUnwrap(viewModel.arquivoExportado?.url)
        XCTAssertEqual(url.lastPathComponent, "Estantes-2026-10-21.json")
        let lido = try BibliotecaExportadaV1().decodificar(Data(contentsOf: url))
        XCTAssertEqual(lido.estantes, [escritorio])
    }

    func testFalhaAoLerABibliotecaAvisaSemAbrirACompartilhar() async {
        repositorio.falharAoLer = true
        let viewModel = fazerViewModel()

        await viewModel.exportarBiblioteca()

        XCTAssertNil(viewModel.arquivoExportado)
        XCTAssertEqual(viewModel.aviso?.titulo, "Exportação não concluída")
    }

    // MARK: Importar

    func testLerArquivoMostraOResumoSemGravarNada() throws {
        let viewModel = fazerViewModel()

        viewModel.lerArquivo(try arquivoDeBackup())

        XCTAssertEqual(viewModel.importacaoPendente?.resumo, "2 livros · 1 estante · 1 categoria")
        XCTAssertEqual(repositorio.substituicoes, 0)
    }

    func testConfirmarImportaUmaVezAvisaEPedeParaRecarregarOInicio() async throws {
        let viewModel = fazerViewModel()
        viewModel.lerArquivo(try arquivoDeBackup())

        let mudou = await viewModel.confirmarImportacao(.mesclar)

        XCTAssertEqual(repositorio.substituicoes, 1)
        XCTAssertEqual(repositorio.livrosGuardados.count, 2)
        XCTAssertNil(viewModel.importacaoPendente)
        XCTAssertEqual(viewModel.aviso?.titulo, "Biblioteca importada")
        XCTAssertTrue(mudou)
    }

    func testCancelarDescartaOArquivoLidoSemGravar() throws {
        let viewModel = fazerViewModel()
        viewModel.lerArquivo(try arquivoDeBackup())

        viewModel.cancelarImportacao()

        XCTAssertNil(viewModel.importacaoPendente)
        XCTAssertEqual(repositorio.substituicoes, 0)
    }

    func testArquivoDeVersaoMaisNovaPedeParaAtualizarOApp() throws {
        let viewModel = fazerViewModel()

        viewModel.lerArquivo(try gravar(Data(#"{ "versao": 2 }"#.utf8), como: "novo.json"))

        XCTAssertNil(viewModel.importacaoPendente)
        XCTAssertEqual(viewModel.aviso?.titulo, "Arquivo de uma versão mais nova")
    }

    func testArquivoQueNaoEhBackupAvisaQueEhInvalido() throws {
        let viewModel = fazerViewModel()

        viewModel.lerArquivo(try gravar(Data("lista de compras".utf8), como: "outro.json"))

        XCTAssertNil(viewModel.importacaoPendente)
        XCTAssertEqual(viewModel.aviso?.titulo, "Arquivo inválido")
    }

    func testFalhaAoGravarAvisaQueNadaMudou() async throws {
        let viewModel = fazerViewModel()
        viewModel.lerArquivo(try arquivoDeBackup())
        repositorio.falharAoGravar = true

        let mudou = await viewModel.confirmarImportacao(.substituir)

        XCTAssertEqual(viewModel.aviso?.titulo, "Importação não concluída")
        XCTAssertFalse(mudou)
    }

    // MARK: Exemplos

    func testSemAcaoDeExemplosOItemNaoAparece() {
        XCTAssertFalse(fazerViewModel().podeCarregarExemplos)
    }

    func testCarregarExemplosChamaAAcaoEPedeParaRecarregarOInicio() async {
        var chamadas = 0
        let viewModel = fazerViewModel(carregarExemplos: { chamadas += 1 })

        let mudou = await viewModel.carregarExemplos()

        XCTAssertTrue(viewModel.podeCarregarExemplos)
        XCTAssertEqual(chamadas, 1)
        XCTAssertTrue(mudou)
    }
}
