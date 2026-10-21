import XCTest
@testable import Estantes

/// O JSON literal abaixo foi escrito à mão a partir do formato decidido em 21/10 (F1–F4) e congela as chaves
/// do v1: renomear um campo do Domínio sem cuidar do arquivo faz este teste falhar.
final class BibliotecaExportadaV1Tests: XCTestCase {
    private let codificador = BibliotecaExportadaV1()

    private let idCivil = UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!
    private let idEscritorio = UUID(uuidString: "E0000000-0000-0000-0000-000000000001")!
    private let idTomo48 = UUID(uuidString: "B0000000-0000-0000-0000-000000000048")!
    private let idItem = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!

    private let jsonV1 = """
    {
      "versao": 1,
      "categorias": [
        { "id": "C0000000-0000-0000-0000-000000000001", "nome": "Civil", "cor": "laranja" }
      ],
      "estantes": [
        {
          "id": "E0000000-0000-0000-0000-000000000001",
          "nome": "Escritório",
          "criadaEm": "2026-10-01T09:00:00.000Z",
          "livros": [
            {
              "id": "B0000000-0000-0000-0000-000000000048",
              "titulo": "Tratado de direito privado",
              "autores": ["Miranda, Pontes de"],
              "colaboradores": [{ "nome": "Bastos, Aurélio Wander", "papel": "prefácio" }],
              "volume": 48,
              "volumeRotulo": "Tomo XLVIII",
              "ano": 1965,
              "cddirCaminho": ["Direito privado", "Direito civil"],
              "origem": "lexml",
              "categoriaIds": ["C0000000-0000-0000-0000-000000000001"],
              "itensSumario": [
                { "id": "A0000000-0000-0000-0000-000000000001", "nivel": 3, "numeracao": "§ 5.108",
                  "titulo": "Conceito e natureza do contrato coletivo", "pagina": "3", "origem": "foto" }
              ],
              "adicionadoEm": "2026-10-21T14:56:43.000Z"
            }
          ]
        }
      ]
    }
    """

    private func decodificar(_ json: String) throws -> ConteudoDaBiblioteca {
        try codificador.decodificar(Data(json.utf8))
    }

    // MARK: Leitura do formato congelado

    func testJSONV1EscritoAMaoEhLidoNosValoresEsperados() throws {
        let conteudo = try decodificar(jsonV1)

        XCTAssertEqual(conteudo.categorias, [Categoria(id: idCivil, nome: "Civil", cor: .laranja)])
        // 2026-10-01T09:00:00Z e 2026-10-21T14:56:43Z em segundos desde 1970, calculados fora do Swift (Python, UTC).
        XCTAssertEqual(conteudo.estantes,
                       [Estante(id: idEscritorio, nome: "Escritório", criadaEm: Date(timeIntervalSince1970: 1_790_845_200))])
        XCTAssertEqual(conteudo.livros, [
            Livro(id: idTomo48, estanteId: idEscritorio, titulo: "Tratado de direito privado",
                  autores: ["Miranda, Pontes de"],
                  colaboradores: [Colaborador(nome: "Bastos, Aurélio Wander", papel: "prefácio")],
                  volume: 48, volumeRotulo: "Tomo XLVIII", ano: 1965,
                  cddirCaminho: ["Direito privado", "Direito civil"], origem: .lexml, categoriaIds: [idCivil],
                  itensSumario: [ItemSumario(id: idItem, nivel: 3, numeracao: "§ 5.108",
                                             titulo: "Conceito e natureza do contrato coletivo", pagina: "3", origem: .foto)],
                  adicionadoEm: Date(timeIntervalSince1970: 1_792_594_603)),
        ])
    }

    // MARK: Ida e volta

    func testIdaEVoltaComTodosOsCamposPreenchidos() throws {
        let conteudo = ConteudoDaBiblioteca(
            estantes: [Estante(id: idEscritorio, nome: "Escritório", criadaEm: Date(timeIntervalSince1970: 1_790_845_200))],
            categorias: [Categoria(id: idCivil, nome: "Civil", cor: .laranja)],
            livros: [Livro(
                id: idTomo48, estanteId: idEscritorio, titulo: "Tratado de direito privado",
                subtitulo: "Direito das obrigações", autores: ["Miranda, Pontes de"],
                colaboradores: [Colaborador(nome: "Bastos, Aurélio Wander", papel: "prefácio")],
                editora: "Borsoi", local: "Rio de Janeiro", edicao: "2.ª ed.", volume: 48, volumeRotulo: "Tomo XLVIII",
                parte: "Parte especial", serie: "Coleção", artigosInicio: 1710, artigosFim: 1779, ano: 1965,
                isbn13: "9780306406157", paginas: 512, cddir: "341.2", cddirCaminho: ["Direito privado"],
                urn: "urn:lex:br:rede.virtual.bibliotecas:livro:1965;000000001", origem: .gemini,
                prateleira: "caixa azul", categoriaIds: [idCivil],
                itensSumario: [ItemSumario(id: idItem, nivel: 1, numeracao: "I", titulo: "Conceito", pagina: "xi", origem: .lexml)],
                adicionadoEm: Date(timeIntervalSince1970: 1_792_594_603)
            )]
        )
        XCTAssertEqual(try codificador.decodificar(codificador.codificar(conteudo)), conteudo)
    }

    func testIdaEVoltaSoComOsCamposObrigatorios() throws {
        let conteudo = ConteudoDaBiblioteca(
            estantes: [Estante(id: idEscritorio, nome: "Escritório", criadaEm: Date(timeIntervalSince1970: 1_790_845_200))],
            livros: [Livro(id: idTomo48, estanteId: idEscritorio, titulo: "Sem nada",
                           adicionadoEm: Date(timeIntervalSince1970: 1_792_594_603))]
        )
        XCTAssertEqual(try codificador.decodificar(codificador.codificar(conteudo)), conteudo)
    }

    /// F2: a data vai com milissegundos; o que passa disso se perde (e só isso).
    func testDataComMaisQueMilissegundosVoltaArredondadaAoMilissegundo() throws {
        let original = Date(timeIntervalSince1970: 1_792_594_603.738_4)
        let conteudo = ConteudoDaBiblioteca(estantes: [Estante(id: idEscritorio, nome: "Escritório", criadaEm: original)])

        let devolvida = try XCTUnwrap(codificador.decodificar(codificador.codificar(conteudo)).estantes.first).criadaEm

        XCTAssertEqual(devolvida.timeIntervalSince1970, 1_792_594_603.738, accuracy: 0.000_1)
    }

    /// F3: opcional vazio sai sem chave (nada de `null`); F4: chaves em ordem e `categoriaIds` ordenados.
    func testSaidaOmiteOpcionaisVaziosEEhDeterministica() throws {
        let ids = (1...5).map { UUID(uuidString: "C0000000-0000-0000-0000-00000000000\($0)")! }
        let livro = Livro(id: idTomo48, estanteId: idEscritorio, titulo: "Sem nada", categoriaIds: Set(ids),
                          adicionadoEm: Date(timeIntervalSince1970: 1_792_594_603))
        let conteudo = ConteudoDaBiblioteca(
            estantes: [Estante(id: idEscritorio, nome: "Escritório", criadaEm: Date(timeIntervalSince1970: 1_790_845_200))],
            categorias: ids.map { Categoria(id: $0, nome: $0.uuidString, cor: .cinza) },
            livros: [livro]
        )

        let texto = String(decoding: try codificador.codificar(conteudo), as: UTF8.self)

        XCTAssertFalse(texto.contains("null"))
        XCTAssertFalse(texto.contains("isbn13"))
        // Um `Set` não tem ordem; com 5 ids, sair ordenado por acaso tem chance de 1 em 120.
        let emOrdem = #""C0000000-0000-0000-0000-000000000001",\s+"C0000000-0000-0000-0000-000000000002",\s+"#
            + #""C0000000-0000-0000-0000-000000000003",\s+"C0000000-0000-0000-0000-000000000004",\s+"#
            + #""C0000000-0000-0000-0000-000000000005""#
        XCTAssertNotNil(texto.range(of: emOrdem, options: .regularExpression))
        XCTAssertEqual(try codificador.codificar(conteudo), try codificador.codificar(conteudo))
    }

    // MARK: Arquivos que não podem ser lidos

    func testVersaoMaisNovaEhRecusadaComONumeroDela() {
        XCTAssertThrowsError(try decodificar(#"{ "versao": 2, "qualquerCoisa": [] }"#)) { erro in
            XCTAssertEqual(erro as? ErroDeImportacao, .versaoMaisNova(2))
        }
    }

    func testCorDesconhecidaTornaOArquivoInvalido() {
        let json = jsonV1.replacingOccurrences(of: "\"laranja\"", with: "\"azul\"")
        XCTAssertThrowsError(try decodificar(json)) { erro in
            XCTAssertEqual(erro as? ErroDeImportacao, .arquivoInvalido)
        }
    }

    func testListaObrigatoriaAusenteTornaOArquivoInvalido() {
        let json = jsonV1.replacingOccurrences(of: "\"autores\": [\"Miranda, Pontes de\"],", with: "")
        XCTAssertThrowsError(try decodificar(json)) { erro in
            XCTAssertEqual(erro as? ErroDeImportacao, .arquivoInvalido)
        }
    }

    func testTextoQueNaoEhJSONTornaOArquivoInvalido() {
        XCTAssertThrowsError(try decodificar("não sou um backup")) { erro in
            XCTAssertEqual(erro as? ErroDeImportacao, .arquivoInvalido)
        }
    }
}
