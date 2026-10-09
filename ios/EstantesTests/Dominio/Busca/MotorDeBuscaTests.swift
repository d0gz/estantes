import XCTest
@testable import Estantes

final class MotorDeBuscaTests: XCTestCase {
    private let estante1 = UUID()
    private let estante2 = UUID()

    private lazy var livroA = Livro(
        estanteId: estante1,
        titulo: "Prisão preventiva",
        itensSumario: [ItemSumario(nivel: 1, titulo: "Prisão em flagrante")]
    )
    private lazy var livroB = Livro(
        estanteId: estante1,
        titulo: "Processo penal",
        itensSumario: ["Prisão", "Recursos", "Provas"].map { ItemSumario(nivel: 1, titulo: $0) }
    )
    private lazy var livroC = Livro(estanteId: estante2, titulo: "Direito civil", editora: "Saraiva")
    private lazy var livroD = Livro(estanteId: estante2, titulo: "Prevenção de litígios")
    private lazy var motor = MotorDeBusca(livros: [livroA, livroB, livroC, livroD], categorias: [])

    private func ids(_ resultados: [ResultadoBusca]) -> [UUID] {
        resultados.map { $0.livro.id }
    }

    private func nota(de livro: Livro, em resultados: [ResultadoBusca]) -> Double? {
        resultados.first { $0.livro.id == livro.id }?.nota
    }

    // MARK: - E entre os termos

    func testExigeTodosOsTermos() {
        XCTAssertEqual(ids(motor.buscar("prisão preventiva").resultados), [livroA.id])
        XCTAssertEqual(ids(motor.buscar("prisão civil").resultados), [])
    }

    func testOrdenaPelaNota() {
        // A tem "prisão" no título (peso 3); B, só no sumário.
        XCTAssertEqual(ids(motor.buscar("prisao").resultados), [livroA.id, livroB.id])
    }

    // MARK: - Plural (2.3i)

    func testPluralAchaOSingular() {
        XCTAssertEqual(ids(motor.buscar("prisoes").resultados), [livroA.id, livroB.id])
        XCTAssertEqual(ids(motor.buscar("prisoes preventivas").resultados), [livroA.id])
    }

    func testPrefixoDoPluralNoMeioDaPalavraAchaOSingular() {
        let plural = Livro(estanteId: estante1, titulo: "Medidas cautelares")
        let motor = MotorDeBusca(livros: [livroA, plural], categorias: [])
        // O usuário ainda está digitando "cautelares": "cautelare" casa pela palavra escrita.
        XCTAssertEqual(ids(motor.buscar("cautelare").resultados), [plural.id])
        XCTAssertEqual(ids(motor.buscar("cautelar").resultados), [plural.id])
    }

    // MARK: - Correção de digitação (2.3i)

    func testCorrigeTermoQueNaoExiste() {
        let resposta = motor.buscar("procesos penal")
        XCTAssertEqual(ids(resposta.resultados), [livroB.id])
        XCTAssertEqual(resposta.correcoes, [Correcao(digitado: "procesos", usado: "processo")])
    }

    func testCorrigeOUltimoSoSeOPrefixoNaoAchouNada() {
        // "prevent" é prefixo de "preventiva": não é erro, o usuário ainda está digitando.
        XCTAssertEqual(motor.buscar("prevent").correcoes, [])
        let resposta = motor.buscar("previntiva")
        XCTAssertEqual(ids(resposta.resultados), [livroA.id])
        XCTAssertEqual(resposta.correcoes, [Correcao(digitado: "previntiva", usado: "preventiva")])
    }

    func testNaoCorrigeTermoQueExiste() {
        let resposta = motor.buscar("prisao civil")
        XCTAssertEqual(resposta.resultados, [])
        XCTAssertEqual(resposta.correcoes, [])
    }

    func testNaoCorrigePalavraCurtaNemNumero() {
        // "civl" tem 4 letras; "1710" tem dígitos.
        XCTAssertEqual(motor.buscar("civl direito").correcoes, [])
        XCTAssertEqual(motor.buscar("1710 direito").correcoes, [])
    }

    func testCorrigirFalseDesliga() {
        let resposta = motor.buscar("procesos penal", corrigir: false)
        XCTAssertEqual(resposta.resultados, [])
        XCTAssertEqual(resposta.correcoes, [])
    }

    func testCorrecaoQueRepeteUmTermoContaUmaVez() {
        XCTAssertEqual(motor.buscar("processo procesos").resultados, motor.buscar("processo").resultados)
    }

    func testEmpateNaCorrecaoVaiParaQuemEstaEmMaisLivrosDepoisOrdemAlfabetica() {
        let banal = Livro(estanteId: estante1, titulo: "Banal")
        let canal = Livro(estanteId: estante1, titulo: "Canal")
        // "vanal" está a 1 de "banal" e de "canal", ambos em um livro: vence a ordem alfabética.
        let doisLivros = MotorDeBusca(livros: [banal, canal], categorias: [])
        XCTAssertEqual(doisLivros.buscar("vanal").correcoes.first?.usado, "banal")
        // Com "canal" em dois livros, ele vence.
        let outroCanal = Livro(estanteId: estante2, titulo: "Canal")
        let tresLivros = MotorDeBusca(livros: [banal, canal, outroCanal], categorias: [])
        XCTAssertEqual(tresLivros.buscar("vanal").correcoes.first?.usado, "canal")
    }

    // MARK: - Prefixo

    func testUltimoTermoValeComoPrefixo() {
        XCTAssertEqual(ids(motor.buscar("prevent").resultados), [livroA.id])
        XCTAssertEqual(ids(motor.buscar("prevenc").resultados), [livroD.id])
        XCTAssertEqual(Set(ids(motor.buscar("prev").resultados)), [livroA.id, livroD.id])
    }

    func testSoOUltimoTermoValeComoPrefixo() {
        XCTAssertEqual(ids(motor.buscar("prisao prevent").resultados), [livroA.id])
        XCTAssertEqual(ids(motor.buscar("prevent prisao").resultados), [])
    }

    func testPrefixoDeUmaLetraNaoExpande() {
        XCTAssertEqual(ids(motor.buscar("c").resultados), [])
        XCTAssertEqual(ids(motor.buscar("ci").resultados), [livroC.id])
    }

    func testPrefixoFicaComAMaiorNotaEntreAsExpansoes() {
        let livro = Livro(estanteId: estante1, titulo: "Prevenção preventiva")
        let motor = MotorDeBusca(livros: [livro, livroC], categorias: [])

        let prefixo = nota(de: livro, em: motor.buscar("prev").resultados) ?? 0
        let prevencao = nota(de: livro, em: motor.buscar("prevencao").resultados) ?? 0
        let preventiva = nota(de: livro, em: motor.buscar("preventiva").resultados) ?? 0

        XCTAssertGreaterThan(prevencao, 0)
        XCTAssertEqual(prefixo, max(prevencao, preventiva))
        XCTAssertLessThan(prefixo, prevencao + preventiva)
    }

    func testTermoRepetidoContaUmaVez() {
        XCTAssertEqual(motor.buscar("penal penal").resultados, motor.buscar("penal").resultados)
        XCTAssertEqual(motor.buscar("prisao penal prisao").resultados, motor.buscar("penal prisao").resultados)
    }

    func testUltimoTermoRepetidoNaoExpande() {
        // "prev" não é termo do vocabulário: repetido, vale como exato e não acha nada.
        XCTAssertEqual(Set(ids(motor.buscar("prev").resultados)), [livroA.id, livroD.id])
        XCTAssertEqual(ids(motor.buscar("prev prev").resultados), [])
    }

    // MARK: - Filtro

    func testFiltroQueAceitaTodosNaoMudaNada() {
        let semFiltro = motor.buscar("prisao").resultados

        // A e B estão na estante 1.
        XCTAssertEqual(motor.buscar("prisao", filtro: FiltroBusca(estanteIds: [estante1])).resultados, semFiltro)
        XCTAssertEqual(motor.buscar("prisao", filtro: FiltroBusca(estanteIds: [estante2])).resultados, [])
    }

    func testFiltroDeAutorCDDirECategoriaComConsulta() {
        let penal = UUID()
        var a = livroA
        a.autores = ["Nucci, Guilherme de Souza"]
        a.cddir = "341.43"
        a.categoriaIds = [penal]
        var motor = self.motor
        motor.atualizar(a)

        XCTAssertEqual(ids(motor.buscar("prisao", filtro: FiltroBusca(autor: "nucci")).resultados), [livroA.id])
        XCTAssertEqual(ids(motor.buscar("prisao", filtro: FiltroBusca(prefixoCDDir: "341.4")).resultados), [livroA.id])
        XCTAssertEqual(ids(motor.buscar("prisao", filtro: FiltroBusca(categoriaIds: [penal])).resultados), [livroA.id])
        XCTAssertEqual(ids(motor.buscar("prisao", filtro: FiltroBusca(autor: "nucci", prefixoCDDir: "342")).resultados), [])
    }

    func testFiltroTiraLivroSemMudarANotaDosOutros() {
        var livroBComAno = livroB
        livroBComAno.ano = 2020
        var motor = self.motor
        motor.atualizar(livroBComAno)

        let semFiltro = motor.buscar("prisao").resultados
        let comFiltro = motor.buscar("prisao", filtro: FiltroBusca(anoMinimo: 2000)).resultados

        XCTAssertEqual(ids(comFiltro), [livroB.id])
        XCTAssertEqual(nota(de: livroB, em: comFiltro), nota(de: livroB, em: semFiltro))
    }

    // MARK: - Consulta vazia

    func testConsultaVaziaSemFiltroNaoDevolveNada() {
        XCTAssertEqual(motor.buscar("").resultados, [])
        XCTAssertEqual(motor.buscar("   ").resultados, [])
        XCTAssertEqual(motor.buscar("de").resultados, [])
    }

    func testConsultaSoComPalavraVaziaEFiltroListaPeloFiltro() {
        let filtro = FiltroBusca(estanteIds: [estante2])

        XCTAssertEqual(motor.buscar("de", filtro: filtro).resultados, motor.buscar("", filtro: filtro).resultados)
    }

    func testConsultaVaziaComFiltroListaEmOrdemDeTitulo() {
        let resultados = motor.buscar("", filtro: FiltroBusca(estanteIds: [estante2])).resultados

        // "Direito civil" antes de "Prevenção de litígios"
        XCTAssertEqual(ids(resultados), [livroC.id, livroD.id])
        XCTAssertTrue(resultados.allSatisfy { $0.nota == 0 })
    }

    // MARK: - Ordem

    func testEmpateDeNotaVaiPeloTitulo() {
        let zeta = Livro(estanteId: estante1, titulo: "Zeta civil")
        let alfa = Livro(estanteId: estante1, titulo: "Alfa civil")
        let motor = MotorDeBusca(livros: [zeta, alfa], categorias: [])

        let resultados = motor.buscar("civil").resultados

        XCTAssertEqual(resultados.map(\.nota)[0], resultados.map(\.nota)[1])
        XCTAssertEqual(ids(resultados), [alfa.id, zeta.id])
    }

    // MARK: - Alteração

    func testAtualizarReindexaOLivro() {
        var motor = self.motor
        var renomeado = livroC
        renomeado.titulo = "Direito tributário"
        motor.atualizar(renomeado)

        XCTAssertEqual(ids(motor.buscar("tributario").resultados), [livroC.id])
        XCTAssertEqual(ids(motor.buscar("civil").resultados), [])
        XCTAssertEqual(motor.buscar("tributario").resultados.first?.livro, renomeado)
    }

    func testRemoverTiraDaBuscaEDaListagemPorFiltro() {
        var motor = self.motor
        motor.remover(livroId: livroC.id)

        XCTAssertEqual(ids(motor.buscar("civil").resultados), [])
        XCTAssertEqual(ids(motor.buscar("", filtro: FiltroBusca(estanteIds: [estante2])).resultados), [livroD.id])
    }

    func testRemoverIdAusenteNaoFazNada() {
        var motor = self.motor
        motor.remover(livroId: UUID())

        XCTAssertEqual(ids(motor.buscar("prisao").resultados), [livroA.id, livroB.id])
    }

    // MARK: - Item do sumário

    private func item(_ resultados: [ResultadoBusca], de livro: Livro) -> String? {
        resultados.first { $0.livro.id == livro.id }?.itemDoSumario?.titulo
    }

    func testMostraOItemQueCasaComAConsulta() {
        let resultados = motor.buscar("prisao").resultados

        XCTAssertEqual(item(resultados, de: livroA), "Prisão em flagrante")
        XCTAssertEqual(item(resultados, de: livroB), "Prisão")
    }

    func testItemPeloPrefixoDoUltimoTermo() {
        XCTAssertEqual(item(motor.buscar("flagr").resultados, de: livroA), "Prisão em flagrante")
    }

    func testItemQueCasaMaisTermosVence() {
        let livro = Livro(
            estanteId: estante1,
            titulo: "Processo penal",
            itensSumario: [
                ItemSumario(nivel: 1, titulo: "Prisão", pagina: "10"),
                ItemSumario(nivel: 1, titulo: "Prisão temporária", pagina: "42"),
            ]
        )
        let motor = MotorDeBusca(livros: [livro, livroC], categorias: [])

        let escolhido = motor.buscar("prisao temporaria").resultados.first?.itemDoSumario

        XCTAssertEqual(escolhido?.titulo, "Prisão temporária")
        XCTAssertEqual(escolhido?.pagina, "42")
    }

    func testItemComTermoFixoEPrefixoJuntos() {
        let livro = Livro(
            estanteId: estante1,
            titulo: "Processo penal",
            itensSumario: [
                ItemSumario(nivel: 1, titulo: "Prisão preventiva"),
                ItemSumario(nivel: 1, titulo: "Prisão temporária"),
                ItemSumario(nivel: 1, titulo: "Medidas temporárias"),
            ]
        )
        let motor = MotorDeBusca(livros: [livro, livroC], categorias: [])

        // Só o segundo tem o termo fixo "prisao" e uma expansão de "temporar".
        XCTAssertEqual(item(motor.buscar("prisao temporar").resultados, de: livro), "Prisão temporária")
    }

    func testItemComAMelhorExpansaoForaDaOrdemAlfabetica() {
        // "pena" expande para "penal" (alfabeticamente primeiro) e "penas". "penal" está em todos
        // os livros e vale pouco; "penas", só neste item, vale mais: o segundo item deve vencer.
        let livro = Livro(
            estanteId: estante1,
            titulo: "Direito penal",
            itensSumario: [
                ItemSumario(nivel: 1, titulo: "Lei penal"),
                ItemSumario(nivel: 1, titulo: "Aplicação das penas"),
            ]
        )
        let outros = ["Processo penal", "Execução penal"].map { Livro(estanteId: estante1, titulo: $0) }
        let motor = MotorDeBusca(livros: [livro] + outros, categorias: [])

        XCTAssertEqual(item(motor.buscar("pena").resultados, de: livro), "Aplicação das penas")
    }

    func testEmpateDeItensFicaComOPrimeiroDoSumario() {
        let livro = Livro(
            estanteId: estante1,
            titulo: "Manual",
            itensSumario: ["Recursos ordinários", "Recursos especiais"].map { ItemSumario(nivel: 1, titulo: $0) }
        )
        let motor = MotorDeBusca(livros: [livro], categorias: [])

        XCTAssertEqual(item(motor.buscar("recursos").resultados, de: livro), "Recursos ordinários")
    }

    func testSemItemQuandoOLivroCasaForaDoSumario() {
        // B casa "processo" pelo título; nenhum item do sumário tem o termo.
        let resultados = motor.buscar("processo").resultados

        XCTAssertEqual(ids(resultados), [livroB.id])
        XCTAssertNil(resultados[0].itemDoSumario)
    }

    func testListagemPorFiltroNaoTemItem() {
        let resultados = motor.buscar("", filtro: FiltroBusca(estanteIds: [estante1])).resultados

        XCTAssertFalse(resultados.isEmpty)
        XCTAssertTrue(resultados.allSatisfy { $0.itemDoSumario == nil })
    }

    // MARK: - Categorias

    func testCategoriaEntraNaBuscaPeloNome() {
        let penal = Categoria(nome: "Criminal", cor: .vermelho)
        var livro = livroB
        livro.categoriaIds = [penal.id]
        let motor = MotorDeBusca(livros: [livro, livroC], categorias: [penal])

        XCTAssertEqual(ids(motor.buscar("criminal").resultados), [livro.id])
    }

    func testRenomearCategoriaReindexaOsLivrosDela() {
        var penal = Categoria(nome: "Criminal", cor: .vermelho)
        var livro = livroB
        livro.categoriaIds = [penal.id]
        var motor = MotorDeBusca(livros: [livro, livroC], categorias: [penal])

        penal.nome = "Penal e penitenciário"
        motor.atualizar(categorias: [penal])

        XCTAssertEqual(ids(motor.buscar("penitenciario").resultados), [livro.id])
        XCTAssertEqual(ids(motor.buscar("criminal").resultados), [])
    }

    func testApagarCategoriaTiraONomeEOId() {
        let penal = Categoria(nome: "Criminal", cor: .vermelho)
        var livro = livroB
        livro.categoriaIds = [penal.id]
        var motor = MotorDeBusca(livros: [livro, livroC], categorias: [penal])

        motor.atualizar(categorias: [])

        XCTAssertEqual(ids(motor.buscar("criminal").resultados), [])
        XCTAssertEqual(motor.buscar("", filtro: FiltroBusca(categoriaIds: [penal.id])).resultados, [])
        XCTAssertEqual(motor.buscar("processo").resultados.first?.livro.categoriaIds, [])
    }

    func testCategoriaNovaComLivroQueJaTinhaOId() {
        let penal = Categoria(nome: "Criminal", cor: .vermelho)
        var livro = livroB
        livro.categoriaIds = [penal.id]
        var motor = MotorDeBusca(livros: [livro, livroC], categorias: [])
        XCTAssertEqual(ids(motor.buscar("criminal").resultados), [])

        motor.atualizar(categorias: [penal])

        XCTAssertEqual(ids(motor.buscar("criminal").resultados), [livro.id])
    }

    func testApagarUmaDeDuasCategoriasMantemAOutra() {
        let penal = Categoria(nome: "Criminal", cor: .vermelho)
        let processo = Categoria(nome: "Processual", cor: .azul)
        var livro = livroB
        livro.categoriaIds = [penal.id, processo.id]
        var motor = MotorDeBusca(livros: [livro, livroC], categorias: [penal, processo])

        motor.atualizar(categorias: [processo])

        XCTAssertEqual(ids(motor.buscar("criminal").resultados), [])
        XCTAssertEqual(ids(motor.buscar("processual").resultados), [livro.id])
        XCTAssertEqual(motor.buscar("processual").resultados.first?.livro.categoriaIds, [processo.id])
    }

    func testAtualizarCategoriasSemMudancaNaoAlteraNada() {
        let penal = Categoria(nome: "Criminal", cor: .vermelho)
        var livro = livroB
        livro.categoriaIds = [penal.id]
        var motor = MotorDeBusca(livros: [livro, livroA, livroC], categorias: [penal])
        let antes = motor.buscar("prisao criminal").resultados

        motor.atualizar(categorias: [penal])

        XCTAssertFalse(antes.isEmpty)
        XCTAssertEqual(motor.buscar("prisao criminal").resultados, antes)
    }

    // MARK: - Obras em vários volumes (2.3b)

    func testArtigoAchaOLivroEMostraOItemPelaNumeracao() {
        let tomo = Livro(
            estanteId: estante1,
            titulo: "Tratado de direito privado",
            itensSumario: [
                ItemSumario(nivel: 1, numeracao: "Art. 1.709 —", titulo: "Bem de família", pagina: "3"),
                ItemSumario(nivel: 1, numeracao: "Art. 1.710 —", titulo: "Bem de família", pagina: "15"),
            ]
        )
        let motor = MotorDeBusca(livros: [tomo, livroC], categorias: [])

        let resultados = motor.buscar("art 1710").resultados

        XCTAssertEqual(ids(resultados), [tomo.id])
        XCTAssertEqual(resultados.first?.itemDoSumario?.pagina, "15")
    }

    func testPalavraSoDaParteAchaOTomo() {
        var tomo = Livro(estanteId: estante1, titulo: "Tratado de direito privado")
        tomo.parte = "Direito das sucessões"
        let motor = MotorDeBusca(livros: [tomo, livroC], categorias: [])

        XCTAssertEqual(ids(motor.buscar("sucessoes").resultados), [tomo.id])
    }

    func testConsultaSemHifenAchaTituloComHifen() {
        let livro = Livro(estanteId: estante1, titulo: "Da sub-rogação")
        let motor = MotorDeBusca(livros: [livro, livroC], categorias: [])

        XCTAssertEqual(ids(motor.buscar("subrogacao").resultados), [livro.id])
        XCTAssertEqual(ids(motor.buscar("sub-rogação").resultados), [livro.id])
    }
}
