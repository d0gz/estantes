import XCTest
@testable import Estantes

/// As ligações do caso de uso: cada modo chega à regra certa, e `ler` passa pela validação.
/// As regras em si estão em `MesclagemTests` e `ValidacaoDaBibliotecaTests`.
final class ImportarBibliotecaTests: XCTestCase {
    private let escritorio = Estante(nome: "Escritório", criadaEm: Date(timeIntervalSince1970: 1_790_845_200))
    private lazy var soNoAparelho = Livro(estanteId: escritorio.id, titulo: "Só no aparelho")
    private lazy var doArquivo = Livro(estanteId: escritorio.id, titulo: "Do arquivo")
    private lazy var repositorio = BibliotecaRepositorioEmMemoria(estantes: [escritorio], livros: [soNoAparelho])
    private lazy var importar = ImportarBiblioteca(repositorio: repositorio, codificador: BibliotecaExportadaV1())

    private var arquivo: ConteudoDaBiblioteca { ConteudoDaBiblioteca(estantes: [escritorio], livros: [doArquivo]) }

    func testMesclarMantemOQueSoExisteNoAparelho() async throws {
        try await importar.importar(arquivo, modo: .mesclar)

        XCTAssertEqual(Set(repositorio.livrosGuardados.keys), [soNoAparelho.id, doArquivo.id])
        XCTAssertEqual(repositorio.substituicoes, 1)
    }

    func testSubstituirDeixaSoOQueEstaNoArquivo() async throws {
        try await importar.importar(arquivo, modo: .substituir)

        XCTAssertEqual(Set(repositorio.livrosGuardados.keys), [doArquivo.id])
        XCTAssertEqual(repositorio.substituicoes, 1)
    }

    func testLerArquivoBemFormadoMasIncoerenteLancaArquivoInvalido() throws {
        // Duas estantes com o mesmo id: o JSON é válido, o conteúdo não.
        let repetidas = ConteudoDaBiblioteca(estantes: [escritorio, escritorio])
        let dados = try BibliotecaExportadaV1().codificar(repetidas)

        XCTAssertThrowsError(try importar.ler(dados)) { erro in
            XCTAssertEqual(erro as? ErroDeImportacao, .arquivoInvalido)
        }
    }

    func testLerArquivoCoerenteDevolveOConteudo() throws {
        let conteudo = ConteudoDaBiblioteca(estantes: [escritorio])
        let dados = try BibliotecaExportadaV1().codificar(conteudo)

        XCTAssertEqual(try importar.ler(dados), conteudo)
    }
}
