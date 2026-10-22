import XCTest
@testable import Estantes

/// O item do checklist da 2.8: exportar → importar → comparar, com o Core Data (em memória) e o formato v1
/// de verdade. O esperado é o conteúdo escrito aqui, não uma releitura do primeiro banco.
final class ExportarImportarTests: XCTestCase {
    func testExportarEImportarNumBancoVazioDevolveAMesmaBiblioteca() async throws {
        let codificador = BibliotecaExportadaV1()
        let origem = try Dependencias.emMemoria().repositorio
        let destino = try Dependencias.emMemoria().repositorio

        // Datas em segundos inteiros: o arquivo guarda milissegundos (F2), e assim a comparação é exata.
        let escritorio = Estante(nome: "Escritório", criadaEm: Date(timeIntervalSince1970: 1_790_845_200))
        let sala = Estante(nome: "Sala", criadaEm: Date(timeIntervalSince1970: 1_790_845_201))
        let civil = Categoria(nome: "Civil", cor: .laranja)
        let filosofia = Categoria(nome: "Filosofia", cor: .marrom)
        let tratado = Livro(
            estanteId: escritorio.id, titulo: "Tratado de direito privado", subtitulo: "Direito das obrigações",
            autores: ["Miranda, Pontes de"], colaboradores: [Colaborador(nome: "Bastos, Aurélio Wander", papel: "prefácio")],
            editora: "Borsoi", volume: 48, volumeRotulo: "Tomo XLVIII", ano: 1965, isbn13: "9780306406157",
            cddirCaminho: ["Direito privado", "Direito civil"], origem: .lexml, prateleira: "caixa azul",
            categoriaIds: [civil.id, filosofia.id],
            itensSumario: [ItemSumario(nivel: 1, titulo: "Nota explicativa", pagina: "ix", origem: .foto),
                           ItemSumario(nivel: 2, numeracao: "§ 5.108", titulo: "Conceito", pagina: "3")],
            adicionadoEm: Date(timeIntervalSince1970: 1_792_594_603)
        )
        let kelsen = Livro(estanteId: sala.id, titulo: "Teoria pura do direito", autores: ["Kelsen, Hans"],
                           adicionadoEm: Date(timeIntervalSince1970: 1_792_594_604))
        for estante in [escritorio, sala] { try await origem.salvar(estante) }
        for categoria in [civil, filosofia] { try await origem.salvar(categoria) }
        for livro in [tratado, kelsen] { try await origem.salvar(livro) }

        let arquivo = try await ExportarBiblioteca(repositorio: origem, codificador: codificador).executar()
        let importar = ImportarBiblioteca(repositorio: destino, codificador: codificador)
        try await importar.importar(importar.ler(arquivo), modo: .substituir)

        let estantes = try await destino.estantes()
        let categorias = try await destino.categorias()
        let livros = try await destino.todosOsLivros()
        XCTAssertEqual(estantes, [escritorio, sala])
        XCTAssertEqual(categorias, [civil, filosofia])
        XCTAssertEqual(livros, [kelsen, tratado])
    }

    /// Revisão E3: mesclar no Core Data de verdade. O que só existe no aparelho fica, com a foto, e o arquivo entra.
    func testExportarEMesclarNumBancoComOutrosLivrosJuntaOsDois() async throws {
        let codificador = BibliotecaExportadaV1()
        let origem = try Dependencias.emMemoria().repositorio
        let destino = try Dependencias.emMemoria().repositorio

        let escritorio = Estante(nome: "Escritório", criadaEm: Date(timeIntervalSince1970: 1_790_845_200))
        let kelsen = Livro(estanteId: escritorio.id, titulo: "Teoria pura do direito",
                           adicionadoEm: Date(timeIntervalSince1970: 1_792_594_603))
        try await origem.salvar(escritorio)
        try await origem.salvar(kelsen)

        let quarto = Estante(nome: "Quarto", criadaEm: Date(timeIntervalSince1970: 1_790_845_100))
        let reale = Livro(estanteId: quarto.id, titulo: "Lições preliminares de direito",
                          adicionadoEm: Date(timeIntervalSince1970: 1_792_594_000))
        try await destino.salvar(quarto)
        try await destino.salvar(reale)
        try await destino.salvarFotoMiniatura(Data([7, 8, 9]), doLivro: reale.id)

        let arquivo = try await ExportarBiblioteca(repositorio: origem, codificador: codificador).executar()
        let importar = ImportarBiblioteca(repositorio: destino, codificador: codificador)
        try await importar.importar(importar.ler(arquivo), modo: .mesclar)

        let estantes = try await destino.estantes()
        let livros = try await destino.todosOsLivros()
        let foto = try await destino.fotoMiniatura(doLivro: reale.id)
        XCTAssertEqual(estantes, [quarto, escritorio])
        XCTAssertEqual(livros, [reale, kelsen])
        XCTAssertEqual(foto, Data([7, 8, 9]))
    }
}
