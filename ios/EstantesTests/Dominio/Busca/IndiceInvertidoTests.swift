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
        XCTAssertEqual(indice.ocorrencias(de: "obrigacao"), [civil.id: [.titulo: 1, .cddirCaminho: 1]])
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
        XCTAssertEqual(indice.ocorrencias(de: "contrato"), [:])
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
        XCTAssertEqual(itens[1].frequencias, ["recurso": 1])
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
        XCTAssertEqual(indice.ocorrencias(de: "contrato"), [civil.id: [.sumario: 1]])
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

    // MARK: - Numeração e parte (2.3b)

    func testNumeracaoDoItemEntraNoSumarioENasFrequenciasDoItem() {
        var indice = IndiceInvertido()
        let item = ItemSumario(nivel: 1, numeracao: "Art. 1.710 —", titulo: "Bem de família")
        let tratado = Livro(estanteId: estanteId, titulo: "Tratado", itensSumario: [item])
        indice.adicionar(tratado, nomesDasCategorias: [:])

        XCTAssertEqual(indice.ocorrencias(de: "1710"), [tratado.id: [.sumario: 1]])
        XCTAssertEqual(indice.ocorrencias(de: "art"), [tratado.id: [.sumario: 1]])
        // art, 1710, bem, familia
        XCTAssertEqual(indice.tamanho(de: .sumario, noLivro: tratado.id), 4)
        let indexado = indice.itensSumario(doLivro: tratado.id).first
        XCTAssertEqual(indexado?.frequencias["1710"], 1)
        XCTAssertEqual(indexado?.tamanho, 4)
    }

    func testParteEntraNoCampoSubtitulo() {
        var indice = IndiceInvertido()
        var tomo = livro(titulo: "Tratado de direito privado", subtitulo: "Parte especial")
        tomo.parte = "Direito das sucessões"
        indice.adicionar(tomo, nomesDasCategorias: [:])

        XCTAssertEqual(indice.ocorrencias(de: "sucessao"), [tomo.id: [.subtitulo: 1]])
        // parte, especial, direito, sucessao
        XCTAssertEqual(indice.tamanho(de: .subtitulo, noLivro: tomo.id), 4)
    }

    func testVolumeRotuloEArtigosEntramNoCampoSubtitulo() {
        var indice = IndiceInvertido()
        var tomo = livro(titulo: "Código civil")
        tomo.volume = 24
        tomo.volumeRotulo = "Volume XXIV"
        tomo.artigosInicio = 1710
        tomo.artigosFim = 1779
        indice.adicionar(tomo, nomesDasCategorias: [:])

        for termo in ["volume", "xxiv", "24", "1710", "1779"] {
            XCTAssertEqual(indice.ocorrencias(de: termo), [tomo.id: [.subtitulo: 1]], termo)
        }
        // Só as pontas do intervalo.
        XCTAssertEqual(indice.ocorrencias(de: "1750"), [:])
        XCTAssertEqual(indice.tamanho(de: .subtitulo, noLivro: tomo.id), 5)
    }

    func testSemVolumeNemArtigosOSubtituloNaoMuda() {
        var indice = IndiceInvertido()
        let simples = livro(titulo: "Código civil", subtitulo: "Comentado")
        indice.adicionar(simples, nomesDasCategorias: [:])

        XCTAssertEqual(indice.tamanho(de: .subtitulo, noLivro: simples.id), 1)
    }

    // MARK: - Plural e prefixo (2.3i)

    func testPluralESingularViramOMesmoTermo() {
        var indice = IndiceInvertido()
        let plural = livro(titulo: "Prisões cautelares")
        let singular = livro(titulo: "Prisão cautelar")
        indice.adicionar(plural, nomesDasCategorias: [:])
        indice.adicionar(singular, nomesDasCategorias: [:])

        XCTAssertEqual(indice.quantidadeDeLivros(contendo: "prisao"), 2)
        XCTAssertEqual(indice.quantidadeDeLivros(contendo: "prisoes"), 0)
    }

    func testPrefixoProcuraNasPalavrasEDevolveOSingular() {
        var indice = IndiceInvertido()
        indice.adicionar(livro(titulo: "Prisões cautelares"), nomesDasCategorias: [:])
        indice.adicionar(livro(titulo: "Prisão cautelar"), nomesDasCategorias: [:])

        // "cautelare" não é prefixo de `cautelar`, mas é de "cautelares".
        XCTAssertEqual(indice.termos(comPrefixo: "cautelare"), ["cautelar"])
        // Duas palavras, um termo: não repete.
        XCTAssertEqual(indice.termos(comPrefixo: "caut"), ["cautelar"])
        XCTAssertEqual(indice.termos(comPrefixo: "pris"), ["prisao"])
    }

    func testPrefixoQueEhPluralCompletoAchaOSingular() {
        var indice = IndiceInvertido()
        indice.adicionar(livro(titulo: "Prisão cautelar"), nomesDasCategorias: [:])

        // Nenhuma palavra começa com "prisoes", mas o singular `prisao` está no índice.
        XCTAssertEqual(indice.termos(comPrefixo: "prisoes"), ["prisao"])
        XCTAssertEqual(indice.termos(comPrefixo: "cautelares"), ["cautelar"])
    }

    func testRemoverTiraAsPalavrasExclusivasDoLivro() {
        var indice = IndiceInvertido()
        let plural = livro(titulo: "Prisões cautelares")
        let singular = livro(titulo: "Prisão cautelar")
        indice.adicionar(plural, nomesDasCategorias: [:])
        indice.adicionar(singular, nomesDasCategorias: [:])

        indice.remover(plural.id)
        // "cautelares" só existia no livro removido; `cautelar` continua pelo outro livro.
        XCTAssertEqual(indice.termos(comPrefixo: "cautelare"), [])
        XCTAssertEqual(indice.termos(comPrefixo: "caut"), ["cautelar"])

        indice.remover(singular.id)
        XCTAssertEqual(indice.termos(comPrefixo: "caut"), [])
    }
}
