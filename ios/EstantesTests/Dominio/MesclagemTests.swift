import XCTest
@testable import Estantes

/// Esperados escritos à mão a partir das decisões de 21/10 (Histórico do PLANO): o arquivo vence por UUID,
/// o que só existe no aparelho fica, categorias de mesmo nome são reaproveitadas ou fundidas.
final class MesclagemTests: XCTestCase {
    private let idEscritorio = UUID(uuidString: "E0000000-0000-0000-0000-000000000001")!
    private let idSala = UUID(uuidString: "E0000000-0000-0000-0000-000000000002")!
    private let idQuarto = UUID(uuidString: "E0000000-0000-0000-0000-000000000003")!
    private let idKelsen = UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!
    private let idReale = UUID(uuidString: "B0000000-0000-0000-0000-000000000002")!
    private let idDiniz = UUID(uuidString: "B0000000-0000-0000-0000-000000000003")!

    func testArquivoVencePorUUIDEOQueSoExisteNumLadoFica() {
        let aparelho = ConteudoDaBiblioteca(
            estantes: [Estante(id: idEscritorio, nome: "Escritório"), Estante(id: idSala, nome: "Sala")],
            livros: [
                Livro(id: idKelsen, estanteId: idEscritorio, titulo: "Teoria pura"),
                Livro(id: idReale, estanteId: idSala, titulo: "Lições preliminares de direito"),
            ]
        )
        let arquivo = ConteudoDaBiblioteca(
            estantes: [Estante(id: idEscritorio, nome: "Escritório de casa"), Estante(id: idQuarto, nome: "Quarto")],
            livros: [
                Livro(id: idKelsen, estanteId: idQuarto, titulo: "Teoria pura do direito"),
                Livro(id: idDiniz, estanteId: idEscritorio, titulo: "Curso de direito civil brasileiro"),
            ]
        )

        let final = Mesclagem.mesclar(aparelho: aparelho, arquivo: arquivo)

        XCTAssertEqual(final.estantes.map(\.id), [idEscritorio, idSala, idQuarto])
        XCTAssertEqual(final.estantes.map(\.nome), ["Escritório de casa", "Sala", "Quarto"])
        XCTAssertEqual(final.livros.map(\.id), [idKelsen, idReale, idDiniz])
        XCTAssertEqual(final.livros.map(\.titulo),
                       ["Teoria pura do direito", "Lições preliminares de direito", "Curso de direito civil brasileiro"])
        // O livro do arquivo vem inteiro, inclusive a estante para onde foi movido.
        XCTAssertEqual(final.livros.map(\.estanteId), [idQuarto, idSala, idEscritorio])
    }

    private let idCivilNoAparelho = UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!
    private let idCivilNoArquivo = UUID(uuidString: "C0000000-0000-0000-0000-000000000009")!

    func testCategoriaComMesmoNomeEOutroUUIDEhReaproveitadaEOsLivrosDoArquivoApontamParaALocal() {
        let estante = Estante(id: idEscritorio, nome: "Escritório")
        let aparelho = ConteudoDaBiblioteca(
            estantes: [estante],
            categorias: [Categoria(id: idCivilNoAparelho, nome: "Civil", cor: .laranja)]
        )
        let arquivo = ConteudoDaBiblioteca(
            estantes: [estante],
            categorias: [Categoria(id: idCivilNoArquivo, nome: "civil", cor: .verde)],
            livros: [Livro(id: idDiniz, estanteId: idEscritorio, titulo: "Curso de direito civil brasileiro",
                           categoriaIds: [idCivilNoArquivo])]
        )

        let final = Mesclagem.mesclar(aparelho: aparelho, arquivo: arquivo)

        XCTAssertEqual(final.categorias, [Categoria(id: idCivilNoAparelho, nome: "Civil", cor: .laranja)])
        XCTAssertEqual(final.livros.map(\.categoriaIds), [[idCivilNoAparelho]])
    }

    private let idProcesso = UUID(uuidString: "C0000000-0000-0000-0000-000000000002")!

    func testCategoriaRenomeadaPeloArquivoParaONomeDeOutraFundeAsDuasNaDoArquivo() {
        let estante = Estante(id: idEscritorio, nome: "Escritório")
        let aparelho = ConteudoDaBiblioteca(
            estantes: [estante],
            categorias: [
                Categoria(id: idCivilNoAparelho, nome: "Civil", cor: .laranja),
                Categoria(id: idProcesso, nome: "Processo", cor: .verde),
            ],
            livros: [
                Livro(id: idDiniz, estanteId: idEscritorio, titulo: "Curso de direito civil brasileiro",
                      categoriaIds: [idCivilNoAparelho]),
                Livro(id: idReale, estanteId: idEscritorio, titulo: "Lições preliminares de direito",
                      categoriaIds: [idProcesso]),
            ]
        )
        let arquivo = ConteudoDaBiblioteca(
            categorias: [Categoria(id: idCivilNoAparelho, nome: "Processo", cor: .roxo)]
        )

        let final = Mesclagem.mesclar(aparelho: aparelho, arquivo: arquivo)

        XCTAssertEqual(final.categorias, [Categoria(id: idCivilNoAparelho, nome: "Processo", cor: .roxo)])
        XCTAssertEqual(final.livros.map(\.categoriaIds), [[idCivilNoAparelho], [idCivilNoAparelho]])
    }

    /// Nasceu verde (o livro do arquivo já vem inteiro); guarda contra juntar os itens dos dois lados.
    func testSumarioDoLivroEhSubstituidoEmBlocoPeloDoArquivo() {
        let estante = Estante(id: idEscritorio, nome: "Escritório")
        let aparelho = ConteudoDaBiblioteca(
            estantes: [estante],
            livros: [Livro(id: idKelsen, estanteId: idEscritorio, titulo: "Teoria pura do direito", itensSumario: [
                ItemSumario(nivel: 1, titulo: "Direito e natureza", pagina: "1"),
                ItemSumario(nivel: 1, titulo: "Direito e moral", pagina: "67"),
            ])]
        )
        let doArquivo = ItemSumario(nivel: 1, numeracao: "I", titulo: "Direito e natureza", pagina: "1", origem: .foto)
        let arquivo = ConteudoDaBiblioteca(
            livros: [Livro(id: idKelsen, estanteId: idEscritorio, titulo: "Teoria pura do direito", itensSumario: [doArquivo])]
        )

        let final = Mesclagem.mesclar(aparelho: aparelho, arquivo: arquivo)

        XCTAssertEqual(final.livros.map(\.itensSumario), [[doArquivo]])
    }
}
