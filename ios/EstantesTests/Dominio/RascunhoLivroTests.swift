import XCTest
@testable import Estantes

final class RascunhoLivroTests: XCTestCase {
    private let escritorio = UUID()
    private let sala = UUID()

    /// Rascunho novo só com os obrigatórios preenchidos.
    private func rascunhoMinimo() -> RascunhoLivro {
        var rascunho = RascunhoLivro(estanteId: escritorio)
        rascunho.titulo = "Teoria pura do direito"
        rascunho.autores = ["Kelsen, Hans"]
        rascunho.editora = "Martins Fontes"
        rascunho.ano = "1998"
        return rascunho
    }

    private func livroCompleto() -> Livro {
        Livro(
            estanteId: escritorio, titulo: "Tratado de direito privado", subtitulo: "Parte especial",
            autores: ["Miranda, Pontes de", "Nery Jr., Nelson"], editora: "Borsoi", local: "Rio de Janeiro",
            edicao: "2.ª ed.", volume: 48, volumeRotulo: "Tomo XLVIII", parte: "Direito de família",
            serie: "Coleção Tratado", artigosInicio: 1710, artigosFim: 1779, ano: 1965, isbn13: "9788520300000",
            paginas: 512, cddir: "341.1", cddirCaminho: ["Direito civil", "Família"], urn: "urn:lex:br:1965",
            origem: .lexml, prateleira: "caixa azul", categoriaIds: [UUID()],
            itensSumario: [ItemSumario(nivel: 1, titulo: "Do casamento")],
            adicionadoEm: Date(timeIntervalSinceReferenceDate: 100)
        )
    }

    // MARK: Novo livro

    func testRascunhoNovoComecaComUmCampoDeAutorVazio() {
        let rascunho = RascunhoLivro(estanteId: escritorio)
        XCTAssertEqual(rascunho.autores, [""])
        XCTAssertEqual(rascunho.estanteId, escritorio)
    }

    func testMontaLivroNovoManualComOsObrigatorios() throws {
        let livro = try XCTUnwrap(rascunhoMinimo().montar(sobre: nil))

        XCTAssertEqual(livro.titulo, "Teoria pura do direito")
        XCTAssertEqual(livro.autores, ["Kelsen, Hans"])
        XCTAssertEqual(livro.editora, "Martins Fontes")
        XCTAssertEqual(livro.ano, 1998)
        XCTAssertEqual(livro.estanteId, escritorio)
        XCTAssertEqual(livro.origem, .manual)
    }

    func testCamposOpcionaisVaziosOuSoDeEspacosViramNil() throws {
        var rascunho = rascunhoMinimo()
        rascunho.subtitulo = "   "
        rascunho.paginas = " "
        rascunho.prateleira = "\n"

        let livro = try XCTUnwrap(rascunho.montar(sobre: nil))

        XCTAssertNil(livro.subtitulo)
        XCTAssertNil(livro.paginas)
        XCTAssertNil(livro.prateleira)
        XCTAssertNil(livro.volume)
    }

    func testAparaEspacosNasPontas() throws {
        var rascunho = rascunhoMinimo()
        rascunho.titulo = "  Teoria pura do direito "
        rascunho.ano = " 1998 "

        let livro = try XCTUnwrap(rascunho.montar(sobre: nil))

        XCTAssertEqual(livro.titulo, "Teoria pura do direito")
        XCTAssertEqual(livro.ano, 1998)
    }

    // MARK: Autores

    func testAutoresVaziosSaemEAOrdemFica() throws {
        var rascunho = rascunhoMinimo()
        rascunho.autores = [" Nery Jr., Nelson ", "", "  ", "Miranda, Pontes de"]

        let livro = try XCTUnwrap(rascunho.montar(sobre: nil))

        XCTAssertEqual(livro.autores, ["Nery Jr., Nelson", "Miranda, Pontes de"])
    }

    func testSemNenhumAutorPreenchidoEhObrigatorio() {
        for autores in [[], [""], ["  ", ""]] {
            var rascunho = rascunhoMinimo()
            rascunho.autores = autores
            XCTAssertEqual(rascunho.problemas(), [.autores: .obrigatorio], "\(autores)")
            XCTAssertNil(rascunho.montar(sobre: nil))
        }
    }

    // MARK: Obrigatórios

    func testRascunhoVazioApontaOsQuatroObrigatorios() {
        let rascunho = RascunhoLivro(estanteId: escritorio)
        XCTAssertEqual(rascunho.problemas(), [
            .titulo: .obrigatorio, .autores: .obrigatorio, .editora: .obrigatorio, .ano: .obrigatorio,
        ])
        XCTAssertNil(rascunho.montar(sobre: nil))
    }

    func testTituloEEditoraSoDeEspacosSaoObrigatorios() {
        var rascunho = rascunhoMinimo()
        rascunho.titulo = "   "
        rascunho.editora = " "
        XCTAssertEqual(rascunho.problemas(), [.titulo: .obrigatorio, .editora: .obrigatorio])
    }

    // MARK: Números

    func testNumeroInvalidoEmCadaCampoNumerico() {
        let invalidos = ["20a", "0", "-3", "1,5", "12 3", "1..710", ".710", "1.", "½", "99999999999999999999"]
        let campos: [(RascunhoLivro.Campo, WritableKeyPath<RascunhoLivro, String>)] = [
            (.ano, \.ano), (.paginas, \.paginas), (.volume, \.volume),
            (.artigosInicio, \.artigosInicio), (.artigosFim, \.artigosFim),
        ]
        for (campo, caminho) in campos {
            for texto in invalidos {
                var rascunho = rascunhoMinimo()
                rascunho[keyPath: caminho] = texto
                XCTAssertEqual(rascunho.problemas()[campo], .numeroInvalido, "\(campo) = \(texto)")
                XCTAssertNil(rascunho.montar(sobre: nil), "\(campo) = \(texto)")
            }
        }
    }

    func testAceitaPontoDeMilharComoNosArtigosImpressos() throws {
        var rascunho = rascunhoMinimo()
        rascunho.artigosInicio = "1.710"
        rascunho.artigosFim = "1.779"
        rascunho.paginas = "1.024"

        let livro = try XCTUnwrap(rascunho.montar(sobre: nil))

        XCTAssertEqual(livro.artigosInicio, 1710)
        XCTAssertEqual(livro.artigosFim, 1779)
        XCTAssertEqual(livro.paginas, 1024)
    }

    func testArtigoFinalAntesDoInicialEhProblema() {
        var rascunho = rascunhoMinimo()
        rascunho.artigosInicio = "1779"
        rascunho.artigosFim = "1.710"
        XCTAssertEqual(rascunho.problemas(), [.artigosFim: .fimAntesDoInicio])
    }

    func testArtigosIguaisOuSoUmaPontaSaoValidos() {
        for (inicio, fim) in [("1710", "1710"), ("1710", ""), ("", "1779")] {
            var rascunho = rascunhoMinimo()
            rascunho.artigosInicio = inicio
            rascunho.artigosFim = fim
            XCTAssertEqual(rascunho.problemas(), [:], "\(inicio)–\(fim)")
        }
    }

    // MARK: Edição

    func testIdaEVoltaSemMudarNadaDevolveOMesmoLivro() {
        let livro = livroCompleto()
        XCTAssertEqual(RascunhoLivro(livro: livro).montar(sobre: livro), livro)
    }

    func testEdicaoPreservaOQueOFormularioNaoMostra() throws {
        let original = livroCompleto()
        var rascunho = RascunhoLivro(livro: original)
        rascunho.titulo = "Tratado de direito privado (reimpr.)"
        rascunho.estanteId = sala

        let editado = try XCTUnwrap(rascunho.montar(sobre: original))

        XCTAssertEqual(editado.titulo, "Tratado de direito privado (reimpr.)")
        XCTAssertEqual(editado.estanteId, sala)
        XCTAssertEqual(editado.id, original.id)
        XCTAssertEqual(editado.adicionadoEm, original.adicionadoEm)
        XCTAssertEqual(editado.origem, .lexml)
        XCTAssertEqual(editado.itensSumario, original.itensSumario)
        XCTAssertEqual(editado.categoriaIds, original.categoriaIds)
        XCTAssertEqual(editado.cddir, original.cddir)
        XCTAssertEqual(editado.cddirCaminho, original.cddirCaminho)
        XCTAssertEqual(editado.urn, original.urn)
    }

    func testEdicaoApagandoUmCampoOpcionalGravaNil() throws {
        let original = livroCompleto()
        var rascunho = RascunhoLivro(livro: original)
        rascunho.volumeRotulo = ""
        rascunho.artigosInicio = ""
        rascunho.artigosFim = ""

        let editado = try XCTUnwrap(rascunho.montar(sobre: original))

        XCTAssertNil(editado.volumeRotulo)
        XCTAssertNil(editado.artigosInicio)
        XCTAssertNil(editado.artigosFim)
    }

    func testLivroImportadoSemEditoraEAnoPedeOsDoisParaSalvar() {
        let importado = Livro(estanteId: escritorio, titulo: "Código civil anotado", autores: ["Nery Jr., Nelson"], origem: .lexml)
        let rascunho = RascunhoLivro(livro: importado)

        XCTAssertEqual(rascunho.autores, ["Nery Jr., Nelson"])
        XCTAssertEqual(rascunho.problemas(), [.editora: .obrigatorio, .ano: .obrigatorio])
        XCTAssertNil(rascunho.montar(sobre: importado))
    }

    func testLivroSemAutoresAbreComUmCampoVazio() {
        let livro = Livro(estanteId: escritorio, titulo: "Constituição federal")
        XCTAssertEqual(RascunhoLivro(livro: livro).autores, [""])
    }
}
