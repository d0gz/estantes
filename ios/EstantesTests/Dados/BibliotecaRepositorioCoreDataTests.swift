import CoreData
import XCTest
@testable import Estantes

/// Especificação do repositório Core Data. Cada teste usa um banco novo em memória (`/dev/null`).
/// Os testes de ida e volta (gravar → ler → comparar) exercitam a conversão em `Conversao.swift`.
final class BibliotecaRepositorioCoreDataTests: XCTestCase {
    private var persistencia: PersistenceController!
    private var repositorio: BibliotecaRepositorioCoreData!

    /// Datas fixas: comparar com `==` não depende do relógio.
    private let data = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override func setUpWithError() throws {
        persistencia = try PersistenceController(emMemoria: true)
        repositorio = BibliotecaRepositorioCoreData(persistencia: persistencia)
    }

    override func tearDown() {
        repositorio = nil
        persistencia = nil
    }

    // MARK: Atalhos

    private func novaEstante(_ nome: String = "Sala") async throws -> Estante {
        let estante = Estante(nome: nome, criadaEm: data)
        try await repositorio.salvar(estante)
        return estante
    }

    /// Quantos objetos de uma entidade existem no banco (para conferir cascatas).
    /// Contexto de fundo com `perform`: o `viewContext` é da fila principal, e o teste não roda nela.
    private func quantidade(de entidade: String) async throws -> Int {
        let contexto = persistencia.container.newBackgroundContext()
        return try await contexto.perform {
            try contexto.count(for: NSFetchRequest<NSManagedObject>(entityName: entidade))
        }
    }

    /// Confere que a chamada lança exatamente `esperado`.
    private func esperarErro(
        _ esperado: ErroPersistencia,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ chamada: () async throws -> Void
    ) async {
        do {
            try await chamada()
            XCTFail("deveria lançar \(esperado)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ErroPersistencia, esperado, file: file, line: line)
        }
    }

    // MARK: Ida e volta

    func testEstanteIdaEVolta() async throws {
        let estante = try await novaEstante("Escritório")
        let lidas = try await repositorio.estantes()
        XCTAssertEqual(lidas, [estante])
    }

    func testCategoriaIdaEVolta() async throws {
        let categoria = Categoria(nome: "Direito Tributário", cor: .verde)
        try await repositorio.salvar(categoria)
        let lidas = try await repositorio.categorias()
        XCTAssertEqual(lidas, [categoria])
    }

    func testLivroCompletoIdaEVolta() async throws {
        let estante = try await novaEstante()
        let categoria = Categoria(nome: "Contratos", cor: .azul)
        try await repositorio.salvar(categoria)

        let livro = Livro(
            estanteId: estante.id,
            titulo: "Curso de direito civil",
            subtitulo: "Contratos",
            autores: ["Gomes, Orlando", "Brito, Edvaldo"],
            editora: "Forense",
            edicao: "28. ed.",
            ano: 2022,
            isbn13: "9788530993962",
            paginas: 712,
            cddir: "341.32",
            cddirCaminho: ["Direito civil", "Obrigações", "Contratos"],
            urn: "urn:lex:br:rede.virtual.bibliotecas:livro:2022;000000000",
            origem: .lexml,
            prateleira: "2ª de cima",
            categoriaIds: [categoria.id],
            itensSumario: [
                ItemSumario(nivel: 1, numeracao: "Parte I", titulo: "Teoria geral", origem: .lexml),
                ItemSumario(nivel: 2, numeracao: "Capítulo 1", titulo: "Conceito de contrato", pagina: 3, origem: .foto),
                ItemSumario(nivel: 2, titulo: "Formação", pagina: 51, origem: .manual),
            ],
            adicionadoEm: data
        )
        try await repositorio.salvar(livro)

        let lido = try await repositorio.livro(id: livro.id)
        XCTAssertEqual(lido, livro)
    }

    func testLivroMinimoMantemOpcionaisNil() async throws {
        let estante = try await novaEstante()
        let livro = Livro(estanteId: estante.id, titulo: "Manual", adicionadoEm: data)
        try await repositorio.salvar(livro)

        let lido = try await repositorio.livro(id: livro.id)
        XCTAssertEqual(lido, livro)
        XCTAssertEqual(lido?.autores, [])
        XCTAssertEqual(lido?.cddirCaminho, [])
        XCTAssertNil(lido?.ano)
    }

    func testSumarioVoltaNaOrdemDoArray() async throws {
        let estante = try await novaEstante()
        // Títulos fora da ordem alfabética, para a ordem só poder vir da posição.
        let titulos = ["Zebra", "Abelha", "Macaco", "Bode", "Tatu"]
        let itens = titulos.map { ItemSumario(nivel: 1, titulo: $0) }
        let livro = Livro(estanteId: estante.id, titulo: "Bichos", itensSumario: itens, adicionadoEm: data)
        try await repositorio.salvar(livro)

        let lido = try await repositorio.livro(id: livro.id)
        XCTAssertEqual(lido?.itensSumario.map(\.titulo), titulos)
    }

    func testLivroInexistenteDevolveNil() async throws {
        let lido = try await repositorio.livro(id: UUID())
        XCTAssertNil(lido)
    }

    // MARK: Atualização

    func testSalvarDuasVezesAtualizaSemDuplicar() async throws {
        var estante = try await novaEstante("Sala")
        estante.nome = "Sala de estar"
        try await repositorio.salvar(estante)

        let lidas = try await repositorio.estantes()
        XCTAssertEqual(lidas, [estante])
    }

    func testAtualizarLivroSubstituiOSumarioEmBloco() async throws {
        let estante = try await novaEstante()
        var livro = Livro(
            estanteId: estante.id,
            titulo: "Livro",
            itensSumario: [ItemSumario(nivel: 1, titulo: "A"), ItemSumario(nivel: 1, titulo: "B"), ItemSumario(nivel: 1, titulo: "C")],
            adicionadoEm: data
        )
        try await repositorio.salvar(livro)

        livro.itensSumario = [ItemSumario(nivel: 1, titulo: "Novo")]
        try await repositorio.salvar(livro)

        let lido = try await repositorio.livro(id: livro.id)
        XCTAssertEqual(lido?.itensSumario.map(\.titulo), ["Novo"])
        let itens = try await quantidade(de: ItemSumarioMO.nomeEntidade)
        XCTAssertEqual(itens, 1, "os itens antigos não podem sobrar no banco")
    }

    func testSalvarLivroNaoApagaAFotoDaCapa() async throws {
        let estante = try await novaEstante()
        var livro = Livro(estanteId: estante.id, titulo: "Com capa", adicionadoEm: data)
        try await repositorio.salvar(livro)
        try await repositorio.salvarFotoCapa(Data([1, 2, 3]), doLivro: livro.id)

        livro.titulo = "Com capa (2. ed.)"
        try await repositorio.salvar(livro)

        let foto = try await repositorio.fotoCapa(doLivro: livro.id)
        XCTAssertEqual(foto, Data([1, 2, 3]))
    }

    // MARK: Erros

    func testSalvarLivroEmEstanteInexistenteLancaErro() async throws {
        let estanteId = UUID()
        let livro = Livro(estanteId: estanteId, titulo: "Órfão")
        do {
            try await repositorio.salvar(livro)
            XCTFail("deveria lançar erro")
        } catch {
            XCTAssertEqual(error as? ErroPersistencia, .estanteNaoEncontrada(estanteId))
        }
    }

    func testSalvarLivroComCategoriaInexistenteLancaErro() async throws {
        let estante = try await novaEstante()
        let categoriaId = UUID()
        let livro = Livro(estanteId: estante.id, titulo: "Etiqueta fantasma", categoriaIds: [categoriaId])
        do {
            try await repositorio.salvar(livro)
            XCTFail("deveria lançar erro")
        } catch {
            XCTAssertEqual(error as? ErroPersistencia, .categoriaNaoEncontrada(categoriaId))
        }
    }

    // MARK: Exclusões

    func testApagarEstanteSemDestinoApagaOsLivrosESumarios() async throws {
        let estante = try await novaEstante()
        let livro = Livro(estanteId: estante.id, titulo: "Vai junto", itensSumario: [ItemSumario(nivel: 1, titulo: "Item")])
        try await repositorio.salvar(livro)

        try await repositorio.apagarEstante(id: estante.id, moverLivrosPara: nil)

        let estantes = try await repositorio.estantes()
        XCTAssertEqual(estantes, [])
        let livros = try await quantidade(de: LivroMO.nomeEntidade)
        XCTAssertEqual(livros, 0)
        let itens = try await quantidade(de: ItemSumarioMO.nomeEntidade)
        XCTAssertEqual(itens, 0)
    }

    func testApagarEstanteComDestinoMoveOsLivros() async throws {
        let origem = try await novaEstante("Origem")
        let destino = try await novaEstante("Destino")
        let livro = Livro(estanteId: origem.id, titulo: "Muda de lugar", adicionadoEm: data)
        try await repositorio.salvar(livro)

        try await repositorio.apagarEstante(id: origem.id, moverLivrosPara: destino.id)

        let estantes = try await repositorio.estantes()
        XCTAssertEqual(estantes, [destino])
        let lido = try await repositorio.livro(id: livro.id)
        XCTAssertEqual(lido?.estanteId, destino.id)
    }

    func testApagarCategoriaSoTiraAEtiqueta() async throws {
        let estante = try await novaEstante()
        let fica = Categoria(nome: "Fica", cor: .azul)
        let sai = Categoria(nome: "Sai", cor: .vermelho)
        try await repositorio.salvar(fica)
        try await repositorio.salvar(sai)
        let livro = Livro(estanteId: estante.id, titulo: "Etiquetado", categoriaIds: [fica.id, sai.id])
        try await repositorio.salvar(livro)

        try await repositorio.apagarCategoria(id: sai.id)

        let lido = try await repositorio.livro(id: livro.id)
        XCTAssertEqual(lido?.categoriaIds, [fica.id])
        let categorias = try await repositorio.categorias()
        XCTAssertEqual(categorias, [fica])
    }

    func testApagarLivroApagaOSumario() async throws {
        let estante = try await novaEstante()
        let livro = Livro(estanteId: estante.id, titulo: "Some", itensSumario: [ItemSumario(nivel: 1, titulo: "Item")])
        try await repositorio.salvar(livro)

        try await repositorio.apagarLivro(id: livro.id)

        let lido = try await repositorio.livro(id: livro.id)
        XCTAssertNil(lido)
        let itens = try await quantidade(de: ItemSumarioMO.nomeEntidade)
        XCTAssertEqual(itens, 0)
    }

    // MARK: Consultas

    func testLivrosNaEstanteSoDaquelaEstanteEPorTitulo() async throws {
        let sala = try await novaEstante("Sala")
        let quarto = try await novaEstante("Quarto")
        for titulo in ["Penal", "Civil"] {
            try await repositorio.salvar(Livro(estanteId: sala.id, titulo: titulo))
        }
        try await repositorio.salvar(Livro(estanteId: quarto.id, titulo: "Tributário"))

        let daSala = try await repositorio.livros(naEstante: sala.id)
        XCTAssertEqual(daSala.map(\.titulo), ["Civil", "Penal"])
        let quantidade = try await repositorio.quantidadeDeLivros(naEstante: sala.id)
        XCTAssertEqual(quantidade, 2)
        let todos = try await repositorio.todosOsLivros()
        XCTAssertEqual(todos.count, 3)
    }

    func testPrateleirasSemRepeticaoNemVazias() async throws {
        let estante = try await novaEstante()
        let outra = try await novaEstante("Outra")
        for prateleira in ["2ª de cima", "caixa azul", "2ª de cima", nil, ""] {
            try await repositorio.salvar(Livro(estanteId: estante.id, titulo: "Livro", prateleira: prateleira))
        }
        try await repositorio.salvar(Livro(estanteId: outra.id, titulo: "Livro", prateleira: "de outra estante"))

        let prateleiras = try await repositorio.prateleiras(naEstante: estante.id)
        XCTAssertEqual(prateleiras, ["2ª de cima", "caixa azul"])
    }

    // MARK: Foto da capa

    func testFotoCapaSalvarLerRemover() async throws {
        let estante = try await novaEstante()
        let livro = Livro(estanteId: estante.id, titulo: "Com foto")
        try await repositorio.salvar(livro)

        try await repositorio.salvarFotoCapa(Data([0xFF, 0xD8]), doLivro: livro.id)
        let salva = try await repositorio.fotoCapa(doLivro: livro.id)
        XCTAssertEqual(salva, Data([0xFF, 0xD8]))

        try await repositorio.salvarFotoCapa(nil, doLivro: livro.id)
        let removida = try await repositorio.fotoCapa(doLivro: livro.id)
        XCTAssertNil(removida)
    }

    // MARK: Revisão da 2.2

    func testApagarEstanteComDestinoIgualAElaMesmaLancaErroSemApagar() async throws {
        let estante = try await novaEstante()
        try await repositorio.salvar(Livro(estanteId: estante.id, titulo: "Fica"))

        await esperarErro(.destinoInvalido(estante.id)) {
            try await self.repositorio.apagarEstante(id: estante.id, moverLivrosPara: estante.id)
        }

        let livros = try await repositorio.quantidadeDeLivros(naEstante: estante.id)
        XCTAssertEqual(livros, 1)
    }

    func testApagarEstanteComDestinoInexistenteLancaErroSemApagar() async throws {
        let estante = try await novaEstante()
        try await repositorio.salvar(Livro(estanteId: estante.id, titulo: "Fica"))
        let destino = UUID()

        await esperarErro(.estanteNaoEncontrada(destino)) {
            try await self.repositorio.apagarEstante(id: estante.id, moverLivrosPara: destino)
        }

        let estantes = try await repositorio.estantes()
        XCTAssertEqual(estantes, [estante])
        let livros = try await repositorio.quantidadeDeLivros(naEstante: estante.id)
        XCTAssertEqual(livros, 1)
    }

    func testEsvaziarOSumarioApagaOsItens() async throws {
        let estante = try await novaEstante()
        var livro = Livro(estanteId: estante.id, titulo: "Livro", itensSumario: [ItemSumario(nivel: 1, titulo: "A")])
        try await repositorio.salvar(livro)

        livro.itensSumario = []
        try await repositorio.salvar(livro)

        let lido = try await repositorio.livro(id: livro.id)
        XCTAssertEqual(lido?.itensSumario, [])
        let itens = try await quantidade(de: ItemSumarioMO.nomeEntidade)
        XCTAssertEqual(itens, 0)
    }

    /// O fluxo normal de edição: a tela muda um item e salva o livro com os MESMOS ids nos itens.
    func testEditarOSumarioMantendoOsIdsNaoDuplica() async throws {
        let estante = try await novaEstante()
        var livro = Livro(
            estanteId: estante.id,
            titulo: "Livro",
            itensSumario: [ItemSumario(nivel: 1, titulo: "A"), ItemSumario(nivel: 1, titulo: "B")],
            adicionadoEm: data
        )
        try await repositorio.salvar(livro)

        livro.itensSumario[1].titulo = "B corrigido"
        livro.itensSumario.swapAt(0, 1)
        try await repositorio.salvar(livro)

        let lido = try await repositorio.livro(id: livro.id)
        XCTAssertEqual(lido, livro)
        let itens = try await quantidade(de: ItemSumarioMO.nomeEntidade)
        XCTAssertEqual(itens, 2)
    }

    func testMudarAEstanteDoLivroPeloSalvar() async throws {
        let sala = try await novaEstante("Sala")
        let quarto = try await novaEstante("Quarto")
        var livro = Livro(estanteId: sala.id, titulo: "Viajante")
        try await repositorio.salvar(livro)

        livro.estanteId = quarto.id
        try await repositorio.salvar(livro)

        let naSala = try await repositorio.livros(naEstante: sala.id)
        let noQuarto = try await repositorio.livros(naEstante: quarto.id)
        XCTAssertEqual(naSala, [])
        XCTAssertEqual(noQuarto.map(\.id), [livro.id])
    }

    /// A regra dos ids inexistentes, documentada na porta.
    func testIdsInexistentes() async throws {
        let nenhum = UUID()
        try await repositorio.apagarEstante(id: nenhum, moverLivrosPara: nil)
        try await repositorio.apagarLivro(id: nenhum)
        try await repositorio.apagarCategoria(id: nenhum)
        let quantidade = try await repositorio.quantidadeDeLivros(naEstante: nenhum)
        XCTAssertEqual(quantidade, 0)
        let prateleiras = try await repositorio.prateleiras(naEstante: nenhum)
        XCTAssertEqual(prateleiras, [])
        let foto = try await repositorio.fotoCapa(doLivro: nenhum)
        XCTAssertNil(foto)

        await esperarErro(.livroNaoEncontrado(nenhum)) {
            try await self.repositorio.salvarFotoCapa(Data([1]), doLivro: nenhum)
        }
    }

    /// O `/dev/null` nunca prova que os dados sobrevivem ao fechar o app. Aqui o banco é um arquivo de
    /// verdade: grava com um controller, abre outro no mesmo arquivo (como ao reabrir o app) e lê.
    func testDadosSobrevivemAReabrirOBanco() async throws {
        let pasta = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        let arquivo = pasta.appendingPathComponent("Estantes.sqlite")

        let estante = Estante(nome: "Persistente", criadaEm: data)
        let livro = Livro(
            estanteId: estante.id,
            titulo: "Sobrevive",
            itensSumario: [ItemSumario(nivel: 1, titulo: "Item")],
            adicionadoEm: data
        )
        do {
            let primeiro = BibliotecaRepositorioCoreData(persistencia: try PersistenceController(arquivo: arquivo))
            try await primeiro.salvar(estante)
            try await primeiro.salvar(livro)
        }

        let reaberto = BibliotecaRepositorioCoreData(persistencia: try PersistenceController(arquivo: arquivo))
        let estantes = try await reaberto.estantes()
        XCTAssertEqual(estantes, [estante])
        let lido = try await reaberto.livro(id: livro.id)
        XCTAssertEqual(lido, livro)
    }
}
