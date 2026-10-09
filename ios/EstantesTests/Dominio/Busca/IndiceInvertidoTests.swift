import XCTest
@testable import Estantes

final class IndiceInvertidoTests: XCTestCase {
    private let estanteId = UUID()

    private func livro(
        id: UUID = UUID(),
        titulo: String,
        subtitulo: String? = nil,
        autores: [String] = [],
        cddirCaminho: [String] = [],
        categoriaIds: Set<UUID> = [],
        sumario: [String] = []
    ) -> Livro {
        Livro(
            id: id,
            estanteId: estanteId,
            titulo: titulo,
            subtitulo: subtitulo,
            autores: autores,
            cddirCaminho: cddirCaminho,
            categoriaIds: categoriaIds,
            itensSumario: sumario.map { ItemSumario(nivel: 1, titulo: $0) }
        )
    }

    func testContaFrequenciaPorCampo() {
        var indice = IndiceInvertido()
        let prisao = livro(titulo: "Prisão preventiva e prisão temporária", autores: ["Lopes Jr., Aury"])
        indice.adicionar(prisao, nomesDasCategorias: [:])

        XCTAssertEqual(indice.ocorrencias(de: "prisao"), [prisao.id: [.titulo: 2]])
        XCTAssertEqual(indice.ocorrencias(de: "aury"), [prisao.id: [.autores: 1]])
        XCTAssertEqual(indice.ocorrencias(de: "inexistente"), [:])
    }

    func testTermoEmDoisCamposContaUmLivroNoDf() {
        var indice = IndiceInvertido()
        let penal = livro(titulo: "Processo penal", sumario: ["Processo cautelar", "Recursos"])
        indice.adicionar(penal, nomesDasCategorias: [:])

        XCTAssertEqual(indice.ocorrencias(de: "processo"), [penal.id: [.titulo: 1, .sumario: 1]])
        XCTAssertEqual(indice.quantidadeDeLivros(contendo: "processo"), 1)
    }

    func testDfETotalDeLivros() {
        var indice = IndiceInvertido()
        indice.adicionar(livro(titulo: "Direito civil"), nomesDasCategorias: [:])
        indice.adicionar(livro(titulo: "Direito penal"), nomesDasCategorias: [:])

        XCTAssertEqual(indice.totalDeLivros, 2)
        XCTAssertEqual(indice.quantidadeDeLivros(contendo: "direito"), 2)
        XCTAssertEqual(indice.quantidadeDeLivros(contendo: "penal"), 1)
        XCTAssertEqual(indice.quantidadeDeLivros(contendo: "tributario"), 0)
    }

    func testTamanhosEMediasContamCamposVazios() {
        var indice = IndiceInvertido()
        let curto = livro(titulo: "Direito civil", subtitulo: "Parte geral")
        let longo = livro(titulo: "Curso de direito processual civil")
        indice.adicionar(curto, nomesDasCategorias: [:])
        indice.adicionar(longo, nomesDasCategorias: [:])

        XCTAssertEqual(indice.tamanho(de: .titulo, noLivro: curto.id), 2)
        XCTAssertEqual(indice.tamanho(de: .titulo, noLivro: longo.id), 4) // "de" é palavra vazia
        XCTAssertEqual(indice.tamanho(de: .subtitulo, noLivro: longo.id), 0)
        XCTAssertEqual(indice.tamanho(de: .titulo, noLivro: UUID()), 0)
        XCTAssertEqual(indice.tamanhoMedio(de: .titulo), 3)
        XCTAssertEqual(indice.tamanhoMedio(de: .subtitulo), 1) // (2 + 0) / 2
    }

    func testCategoriasEntramPeloNomeEIdsSemNomeSaoIgnorados() {
        var indice = IndiceInvertido()
        let tributario = UUID()
        let semNome = UUID()
        let manual = livro(titulo: "Manual", categoriaIds: [tributario, semNome])
        indice.adicionar(manual, nomesDasCategorias: [tributario: "Direito Tributário"])

        XCTAssertEqual(indice.ocorrencias(de: "tributario"), [manual.id: [.categorias: 1]])
        XCTAssertEqual(indice.tamanho(de: .categorias, noLivro: manual.id), 2)
    }

    func testCddirCaminhoEntraNoIndice() {
        var indice = IndiceInvertido()
        let civil = livro(titulo: "Obrigações", cddirCaminho: ["Direito Civil", "Direito das Obrigações"])
        indice.adicionar(civil, nomesDasCategorias: [:])

        XCTAssertEqual(indice.ocorrencias(de: "direito"), [civil.id: [.cddirCaminho: 2]])
        XCTAssertEqual(indice.ocorrencias(de: "obrigacoes"), [civil.id: [.titulo: 1, .cddirCaminho: 1]])
    }

    func testRemoverLimpaTermosExclusivosEAtualizaMedias() {
        var indice = IndiceInvertido()
        let civil = livro(titulo: "Direito civil")
        let penal = livro(titulo: "Direito penal econômico")
        indice.adicionar(civil, nomesDasCategorias: [:])
        indice.adicionar(penal, nomesDasCategorias: [:])

        indice.remover(penal.id)

        XCTAssertEqual(indice.totalDeLivros, 1)
        XCTAssertEqual(indice.ocorrencias(de: "penal"), [:])
        XCTAssertEqual(indice.quantidadeDeLivros(contendo: "penal"), 0)
        XCTAssertEqual(indice.ocorrencias(de: "direito"), [civil.id: [.titulo: 1]])
        XCTAssertEqual(indice.tamanhoMedio(de: .titulo), 2)
    }

    func testRemoverIdInexistenteNaoMudaNada() {
        var indice = IndiceInvertido()
        let civil = livro(titulo: "Direito civil")
        indice.adicionar(civil, nomesDasCategorias: [:])

        indice.remover(UUID())

        XCTAssertEqual(indice.totalDeLivros, 1)
        XCTAssertEqual(indice.quantidadeDeLivros(contendo: "civil"), 1)
    }

    func testAdicionarDeNovoReindexaSemDuplicar() {
        var indice = IndiceInvertido()
        let id = UUID()
        indice.adicionar(livro(id: id, titulo: "Direito civil", sumario: ["Contratos"]), nomesDasCategorias: [:])
        indice.adicionar(livro(id: id, titulo: "Direito penal"), nomesDasCategorias: [:])

        XCTAssertEqual(indice.totalDeLivros, 1)
        XCTAssertEqual(indice.ocorrencias(de: "civil"), [:])
        XCTAssertEqual(indice.ocorrencias(de: "contratos"), [:])
        XCTAssertEqual(indice.ocorrencias(de: "direito"), [id: [.titulo: 1]])
        XCTAssertEqual(indice.tamanhoMedio(de: .sumario), 0)
        XCTAssertEqual(indice.tamanhoMedioDosItens, 0)
    }

    func testGuardaOsItensDoSumarioNaOrdem() {
        var indice = IndiceInvertido()
        let penal = livro(titulo: "Processo penal", sumario: ["Prisão e prisão preventiva", "Recursos"])
        indice.adicionar(penal, nomesDasCategorias: [:])

        let itens = indice.itensSumario(doLivro: penal.id)
        XCTAssertEqual(itens.map(\.id), penal.itensSumario.map(\.id))
        XCTAssertEqual(itens[0].frequencias, ["prisao": 2, "preventiva": 1])
        XCTAssertEqual(itens[0].tamanho, 3)
        XCTAssertEqual(itens[1].frequencias, ["recursos": 1])
        XCTAssertEqual(indice.tamanhoMedioDosItens, 2) // (3 + 1) / 2
        XCTAssertEqual(indice.ocorrencias(de: "prisao"), [penal.id: [.sumario: 2]])
    }

    func testRemoverDesfazSomasDosItensSemMexerNosOutrosLivros() {
        var indice = IndiceInvertido()
        let civil = livro(titulo: "Direito civil", sumario: ["Contratos em espécie"]) // item com 2 termos
        let penal = livro(titulo: "Direito penal", sumario: ["Crimes", "Penas e medidas"]) // 1 e 2 termos
        indice.adicionar(civil, nomesDasCategorias: [:])
        indice.adicionar(penal, nomesDasCategorias: [:])
        XCTAssertEqual(indice.tamanhoMedioDosItens, 5.0 / 3.0)

        indice.remover(penal.id)

        XCTAssertEqual(indice.tamanhoMedioDosItens, 2)
        XCTAssertEqual(indice.tamanhoMedio(de: .sumario), 2)
        XCTAssertEqual(indice.itensSumario(doLivro: penal.id), [])
        XCTAssertEqual(indice.ocorrencias(de: "contratos"), [civil.id: [.sumario: 1]])
    }

    func testReindexarComMesmoConteudoNaoMudaNada() {
        var indice = IndiceInvertido()
        let penal = livro(titulo: "Processo penal", autores: ["Lopes Jr., Aury"], sumario: ["Prisão", "Recursos"])
        let civil = livro(titulo: "Direito civil")
        indice.adicionar(penal, nomesDasCategorias: [:])
        indice.adicionar(civil, nomesDasCategorias: [:])

        indice.adicionar(penal, nomesDasCategorias: [:])

        XCTAssertEqual(indice.totalDeLivros, 2)
        XCTAssertEqual(indice.ocorrencias(de: "penal"), [penal.id: [.titulo: 1]])
        XCTAssertEqual(indice.tamanhoMedio(de: .titulo), 2)
        XCTAssertEqual(indice.tamanhoMedio(de: .sumario), 1)
        XCTAssertEqual(indice.tamanhoMedioDosItens, 1)
    }

    func testReindexarParaLivroMaiorAtualizaTamanhos() {
        var indice = IndiceInvertido()
        let id = UUID()
        indice.adicionar(livro(id: id, titulo: "Penal"), nomesDasCategorias: [:])
        indice.adicionar(livro(id: id, titulo: "Curso de direito penal", sumario: ["Crimes contra a vida"]),
                         nomesDasCategorias: [:])

        XCTAssertEqual(indice.tamanho(de: .titulo, noLivro: id), 3)
        XCTAssertEqual(indice.tamanhoMedio(de: .titulo), 3)
        XCTAssertEqual(indice.tamanhoMedioDosItens, 3)
        XCTAssertEqual(indice.ocorrencias(de: "penal"), [id: [.titulo: 1]])
    }

    func testRemoverEAdicionarDeNovoOMesmoLivro() {
        var indice = IndiceInvertido()
        let civil = livro(titulo: "Direito civil", sumario: ["Contratos"])
        indice.adicionar(civil, nomesDasCategorias: [:])

        indice.remover(civil.id)
        indice.adicionar(civil, nomesDasCategorias: [:])

        XCTAssertEqual(indice.totalDeLivros, 1)
        XCTAssertEqual(indice.ocorrencias(de: "civil"), [civil.id: [.titulo: 1]])
        XCTAssertEqual(indice.tamanhoMedioDosItens, 1)
    }

    func testItemDoSumarioSemTermosContaNaMedia() {
        var indice = IndiceInvertido()
        let penal = livro(titulo: "Processo penal", sumario: ["De", "Prisão preventiva"])
        indice.adicionar(penal, nomesDasCategorias: [:])

        let itens = indice.itensSumario(doLivro: penal.id)
        XCTAssertEqual(itens.count, 2)
        XCTAssertEqual(itens[0].tamanho, 0)
        XCTAssertEqual(itens[0].frequencias, [:])
        XCTAssertEqual(indice.tamanhoMedioDosItens, 1) // (0 + 2) / 2
    }

    func testTermoEmVariosLivrosEVariosCampos() {
        var indice = IndiceInvertido()
        let penal = livro(titulo: "Direito penal", cddirCaminho: ["Direito Penal"])
        let processo = livro(titulo: "Processo", sumario: ["Direito de defesa"])
        indice.adicionar(penal, nomesDasCategorias: [:])
        indice.adicionar(processo, nomesDasCategorias: [:])

        XCTAssertEqual(indice.ocorrencias(de: "direito"), [
            penal.id: [.titulo: 1, .cddirCaminho: 1],
            processo.id: [.sumario: 1],
        ])
        XCTAssertNil(indice.ocorrencias(de: "direito")[processo.id]?[.titulo]) // campo ausente, não 0
        XCTAssertEqual(indice.quantidadeDeLivros(contendo: "direito"), 2)
    }

    func testTodoCampoBuscaEIndexado() {
        var indice = IndiceInvertido()
        let categoria = UUID()
        let completo = Livro(
            estanteId: estanteId,
            titulo: "termo",
            subtitulo: "termo",
            autores: ["termo"],
            cddirCaminho: ["termo"],
            categoriaIds: [categoria],
            itensSumario: [ItemSumario(nivel: 1, titulo: "termo")]
        )
        indice.adicionar(completo, nomesDasCategorias: [categoria: "termo"])

        let campos = indice.ocorrencias(de: "termo")[completo.id] ?? [:]
        for campo in CampoBusca.allCases {
            XCTAssertEqual(campos[campo], 1, "campo \(campo) não foi indexado")
        }
    }

    func testIndiceVazio() {
        let indice = IndiceInvertido()

        XCTAssertEqual(indice.totalDeLivros, 0)
        XCTAssertEqual(indice.tamanhoMedio(de: .titulo), 0)
        XCTAssertEqual(indice.tamanhoMedioDosItens, 0)
        XCTAssertEqual(indice.itensSumario(doLivro: UUID()), [])
    }
}
