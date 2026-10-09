import XCTest
@testable import Estantes

final class BM25FTests: XCTestCase {
    private let estanteId = UUID()
    private let precisao = 0.0001

    private func livro(
        titulo: String,
        autores: [String] = [],
        cddirCaminho: [String] = [],
        sumario: [String] = []
    ) -> Livro {
        Livro(
            estanteId: estanteId,
            titulo: titulo,
            autores: autores,
            cddirCaminho: cddirCaminho,
            itensSumario: sumario.map { ItemSumario(nivel: 1, titulo: $0) }
        )
    }

    private func montarIndice(_ livros: [Livro]) -> IndiceInvertido {
        var indice = IndiceInvertido()
        for livro in livros {
            indice.adicionar(livro, nomesDasCategorias: [:])
        }
        return indice
    }

    // O exemplo calculado à mão no enunciado do passo 3.
    // Título: médio 2 (peso 3, b 0,5). Sumário: médio (2 + 3 + 1) / 3 = 2 (peso 1, b 0,75).
    private lazy var livroA = livro(titulo: "Prisão preventiva", sumario: ["Prisão em flagrante"])
    private lazy var livroB = livro(titulo: "Processo penal", sumario: ["Prisão", "Recursos", "Provas"])
    private lazy var livroC = livro(titulo: "Direito civil", sumario: ["Contratos"])
    private lazy var exemplo = montarIndice([livroA, livroB, livroC])
    /// Os valores do enunciado, fixos aqui: o exemplo testa a fórmula, não o `padrao` calibrado
    /// (que mudou no passo 6).
    private let parametrosDoExemplo = ParametrosBM25F(
        k1: 1.2,
        pesos: [.titulo: 3.0, .subtitulo: 2.0, .categorias: 1.5, .cddirCaminho: 1.5, .sumario: 1.0, .autores: 0.5],
        b: [.titulo: 0.5, .subtitulo: 0.5, .categorias: 0.3, .cddirCaminho: 0.3, .sumario: 0.75, .autores: 0]
    )

    func testIdf() {
        XCTAssertEqual(BM25F.idf(totalDeLivros: 3, livrosComOTermo: 2), 0.4700, accuracy: precisao) // ln 1,6
        XCTAssertEqual(BM25F.idf(totalDeLivros: 3, livrosComOTermo: 1), 0.9808, accuracy: precisao) // ln 8/3
        XCTAssertGreaterThan(BM25F.idf(totalDeLivros: 3, livrosComOTermo: 3), 0)
    }

    func testExemploPrisao() {
        let notas = BM25F.notas(termos: ["prisao"], indice: exemplo, parametros: parametrosDoExemplo)

        // A: título 3·1/1 + sumário 1·1/1 = 4 → 0,4700 · 4/5,2
        XCTAssertEqual(notas[livroA.id] ?? 0, 0.3615, accuracy: precisao)
        // B: sumário 1/1,375 = 0,7273 → 0,4700 · 0,7273/1,9273
        XCTAssertEqual(notas[livroB.id] ?? 0, 0.1774, accuracy: precisao)
        XCTAssertNil(notas[livroC.id])
    }

    func testExemploPrisaoFlagrante() {
        let notas = BM25F.notas(termos: ["prisao", "flagrante"], indice: exemplo, parametros: parametrosDoExemplo)

        // flagrante: 0,9808 · 1/2,2 = 0,4458, somado aos 0,3615 de prisao
        XCTAssertEqual(notas[livroA.id] ?? 0, 0.8074, accuracy: precisao)
        XCTAssertEqual(notas[livroB.id] ?? 0, 0.1774, accuracy: precisao)
    }

    func testTermoEmTodosOsCamposNaoPassaDoIdf() {
        let categoria = UUID()
        let completo = Livro(
            estanteId: estanteId,
            titulo: "Penal penal penal",
            subtitulo: "Penal",
            autores: ["Penal"],
            cddirCaminho: ["Direito Penal"],
            categoriaIds: [categoria],
            itensSumario: [ItemSumario(nivel: 1, titulo: "Penal")]
        )
        var indice = montarIndice([livro(titulo: "Direito civil")])
        indice.adicionar(completo, nomesDasCategorias: [categoria: "Penal"])

        let nota = BM25F.notas(termos: ["penal"], indice: indice)[completo.id] ?? 0
        XCTAssertLessThan(nota, BM25F.idf(totalDeLivros: 2, livrosComOTermo: 1))
    }

    func testRepeticaoSaturaSemDobrarANota() {
        let duas = livro(titulo: "Prisão e prisão") // "e" é palavra vazia: 2 termos, tf 2
        let uma = livro(titulo: "Prisão cautelar") // 2 termos, tf 1
        let notas = BM25F.notas(termos: ["prisao"], indice: montarIndice([duas, uma]))

        let notaDuas = notas[duas.id] ?? 0
        let notaUma = notas[uma.id] ?? 0
        XCTAssertGreaterThan(notaDuas, notaUma)
        XCTAssertLessThan(notaDuas, 2 * notaUma)
    }

    func testCampoMaisLongoTemNotaMenor() {
        let curto = livro(titulo: "Prisão cautelar")
        let longo = livro(titulo: "Prisão cautelar processual penal brasileira")
        let notas = BM25F.notas(termos: ["prisao"], indice: montarIndice([curto, longo]))

        XCTAssertGreaterThan(notas[curto.id] ?? 0, notas[longo.id] ?? 0)
    }

    func testTituloPesaMaisQueAutor() {
        let noTitulo = livro(titulo: "Lopes")
        let noAutor = livro(titulo: "Processo penal", autores: ["Lopes Jr., Aury"])
        let notas = BM25F.notas(
            termos: Tokenizador.termos("Lopes"), indice: montarIndice([noTitulo, noAutor])
        )

        XCTAssertGreaterThan(notas[noTitulo.id] ?? 0, notas[noAutor.id] ?? 0)
        XCTAssertGreaterThan(notas[noAutor.id] ?? 0, 0)
    }

    func testCasosVazios() {
        XCTAssertEqual(BM25F.notas(termos: [], indice: exemplo), [:])
        XCTAssertEqual(BM25F.notas(termos: ["inexistente"], indice: exemplo), [:])
        XCTAssertEqual(BM25F.notas(termos: ["prisao"], indice: IndiceInvertido()), [:])
    }

    func testTermoRepetidoNaConsultaContaUmaVez() {
        XCTAssertEqual(
            BM25F.notas(termos: ["prisao", "prisao"], indice: exemplo),
            BM25F.notas(termos: ["prisao"], indice: exemplo)
        )
    }

    func testNotaDoItemNoExemplo() {
        // Itens: A tem 1 (2 termos), B tem 3 (1 termo cada), C tem 1 (1 termo): média 6/5 = 1,2.
        // Item de A: fator 0,25 + 0,75 · 2/1,2 = 1,5 → tf' 0,6667 → 0,4700 · 0,6667/1,8667
        let item = exemplo.itensSumario(doLivro: livroA.id)[0]
        XCTAssertEqual(BM25F.notaDoItem(item, termos: ["prisao"], indice: exemplo), 0.1679, accuracy: precisao)
    }

    func testItemComOTermoVenceItemSemEItemMaisCurtoVence() {
        let penal = livro(titulo: "Processo penal",
                          sumario: ["Prisão", "Prisão preventiva domiciliar", "Recursos"])
        let indice = montarIndice([penal])
        let itens = indice.itensSumario(doLivro: penal.id)
        let notas = itens.map { BM25F.notaDoItem($0, termos: ["prisao"], indice: indice) }

        XCTAssertGreaterThan(notas[0], notas[1]) // mais curto vence
        XCTAssertGreaterThan(notas[1], 0)
        XCTAssertEqual(notas[2], 0) // sem o termo
    }

    func testItemSemTermosTemNotaZero() {
        let penal = livro(titulo: "Processo penal", sumario: ["De", "Prisão"])
        let indice = montarIndice([penal])
        let vazio = indice.itensSumario(doLivro: penal.id)[0]

        XCTAssertEqual(vazio.tamanho, 0)
        XCTAssertEqual(BM25F.notaDoItem(vazio, termos: ["prisao"], indice: indice), 0)
    }

    // MARK: - Cada campo, com parâmetros próprios

    /// Livro com o texto só no campo pedido; o resto vazio.
    private func livro(com texto: String, em campo: CampoBusca, categoria: UUID) -> Livro {
        var livro = Livro(estanteId: estanteId, titulo: "")
        switch campo {
        case .titulo: livro.titulo = texto
        case .subtitulo: livro.subtitulo = texto
        case .autores: livro.autores = [texto]
        case .categorias: livro.categoriaIds = [categoria]
        case .cddirCaminho: livro.cddirCaminho = [texto]
        case .sumario: livro.itensSumario = [ItemSumario(nivel: 1, titulo: texto)]
        }
        return livro
    }

    func testCadaCampoUsaOProprioPesoEB() {
        // Dois livros: o termo num campo de 2 termos ("alfa beta") e um livro vazio.
        // N = 2, df = 1 → IDF = ln 2. Tamanho médio do campo = (2 + 0) / 2 = 1.
        let idf = log(2.0)
        for campo in CampoBusca.allCases {
            let categoria = UUID()
            let comTermo = livro(com: "alfa beta", em: campo, categoria: categoria)
            var indice = montarIndice([Livro(estanteId: estanteId, titulo: "")])
            indice.adicionar(comTermo, nomesDasCategorias: [categoria: "alfa beta"])

            // b = 0: sem normalização → tf' = 1 → 1/2,2
            let semTamanho = ParametrosBM25F(k1: 1.2, pesos: [campo: 1], b: [campo: 0])
            XCTAssertEqual(BM25F.notas(termos: ["alfa"], indice: indice, parametros: semTamanho)[comTermo.id] ?? 0,
                           idf * 1 / 2.2, accuracy: precisao, "campo \(campo), b = 0")

            // b = 1: fator 2/1 = 2 → tf' = 0,5 → 0,5/1,7
            let comTamanho = ParametrosBM25F(k1: 1.2, pesos: [campo: 1], b: [campo: 1])
            XCTAssertEqual(BM25F.notas(termos: ["alfa"], indice: indice, parametros: comTamanho)[comTermo.id] ?? 0,
                           idf * 0.5 / 1.7, accuracy: precisao, "campo \(campo), b = 1")

            // Peso 2 dobra o tf' antes da saturação: 2/3,2
            let pesoDois = ParametrosBM25F(k1: 1.2, pesos: [campo: 2], b: [campo: 0])
            XCTAssertEqual(BM25F.notas(termos: ["alfa"], indice: indice, parametros: pesoDois)[comTermo.id] ?? 0,
                           idf * 2 / 3.2, accuracy: precisao, "campo \(campo), peso 2")
        }
    }

    func testExtremosValidosDosParametrosDaoNotaFinita() {
        let todosB1 = Dictionary(uniqueKeysWithValues: CampoBusca.allCases.map { ($0, 1.0) })
        let extremos = ParametrosBM25F(k1: 0, pesos: ParametrosBM25F.padrao.pesos, b: todosB1)
        let notas = BM25F.notas(termos: ["prisao", "flagrante"], indice: exemplo, parametros: extremos)

        XCTAssertTrue(notas.values.allSatisfy { $0.isFinite })
        // Com k1 = 0 a saturação vale 1: cada termo contribui exatamente com o seu IDF.
        XCTAssertEqual(notas[livroB.id] ?? 0, 0.4700, accuracy: precisao)
        XCTAssertEqual(notas[livroA.id] ?? 0, 0.4700 + 0.9808, accuracy: precisao)

        let item = exemplo.itensSumario(doLivro: livroA.id)[0]
        XCTAssertTrue(BM25F.notaDoItem(item, termos: ["prisao"], indice: exemplo, parametros: extremos).isFinite)
    }
}
