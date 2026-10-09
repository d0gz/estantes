import Foundation
@testable import Estantes

/// A biblioteca sobre a qual as consultas de referência são medidas (passo 6 da 2.3).
///
/// - 4 livros fotografados (`avaliacao/fotos/`), transcritos à mão: tomos, âncoras ("Art. 1.710",
///   "§ 5.108"), páginas em romanos, ortografia antiga.
/// - 18 registros do LexML, escolhidos em grupos de vizinhos que se confundem (processo penal,
///   constituição, trabalho, civil). Sumário da `descricao` (itens separados por " -- "; item cortado
///   pelo limite de 400 caracteres do CSV foi descartado); autor e CDDir da ficha `/urn`, autor sem
///   o ano de nascimento.
/// - Categorias escolhidas pelo Ricardo, como faria no app.
///
/// UUIDs fixos: o motor desempata pelo título e, por fim, pelo id; com `UUID()` a ordem dos empatados
/// mudaria a cada execução.
enum BibliotecaDeReferencia {
    static let estante = uuid(0)

    // MARK: - Categorias

    private static let processoPenal = Categoria(id: uuid(101), nome: "Processo penal", cor: .vermelho)
    private static let trabalho = Categoria(id: uuid(102), nome: "Trabalho", cor: .laranja)
    private static let constitucional = Categoria(id: uuid(103), nome: "Constitucional", cor: .azul)
    private static let sucessoes = Categoria(id: uuid(104), nome: "Sucessões", cor: .verde)
    private static let historia = Categoria(id: uuid(105), nome: "História", cor: .marrom)

    static let categorias = [processoPenal, trabalho, constitucional, sucessoes, historia]

    // MARK: - Fichas

    /// Em ordem; a chave é o que as consultas usam para dizer qual livro esperam.
    static let fichas: [(chave: String, livro: Livro)] = [
        // Fotografados
        ("lassale", lassale),
        ("carvalho-santos-v24", carvalhoSantosV24),
        ("tratado-t48", tratadoT48),
        ("tratado-t1", tratadoT1),
        // LexML: processo penal
        ("badaro", lexml(
            5, "Processo penal", autor: "Badaró, Gustavo Henrique", ano: 2015,
            cddir: "341.43", caminho: "DIREITO PÚBLICO > DIREITO PROCESSUAL > Direito Processual Penal",
            sumario: "Garantias processuais e o sistema acusatório -- Lei processual penal no tempo, no espaço e sua interpretação -- Inquérito policial e outras formas de investigação preliminar -- Ação penal -- Ação civil ex delicto -- Competência -- Sujeitos processuais -- Questões e processos incidentes -- Comunicação dos atos processuais -- Da prova -- Sentença e coisa julgada -- Do processo",
            categorias: [processoPenal]
        )),
        ("rosa", lexml(
            6, "Teoria dos jogos e processo penal", autor: "Rosa, Alexandre", ano: 2017,
            cddir: "341.43", caminho: "DIREITO PÚBLICO > DIREITO PROCESSUAL > Direito Processual Penal",
            sumario: "Como você aprendeu a tomar decisões? -- O império de recompensas no processo penal -- Para entender a teoria dos jogos no direito -- Entender o processo como jogo -- As recompensas dos jogadores em cada jogo processual -- Estratégias e táticas -- O dispositivo do processo penal : estrutura e funcionamento -- O desafio dos quebra-cabeças processuais reais.",
            categorias: [processoPenal]
        )),
        ("guimaraes", lexml(
            7, "Imputação criminal preliminar e indiciamento", autor: "Guimarães, Johnny Wilson Batista", ano: 2017,
            cddir: "341.4331",
            caminho: "DIREITO PÚBLICO > DIREITO PROCESSUAL > Direito Processual Penal > Instrução penal > Instrução penal propriamente dita. Informação ou pesquisa das provas da imputabilidade",
            sumario: "Processo penal constitucioanal -- Fundamentos da existência do inquérito policial -- A imputação criminal -- O modelo italiano como parâmetro. Breve estudo sobre a indagine preliminare.",
            categorias: [processoPenal]
        )),
        ("capez", lexml(
            8, "Prisão e medidas cautelares diversas", autor: "Capez, Rodrigo", ano: 2017,
            cddir: "341.4326",
            caminho: "DIREITO PÚBLICO > DIREITO PROCESSUAL > Direito Processual Penal > Partes. Ações > Detenção preventiva. Liberdade sob caução. Fiança. Liberdade provisória",
            sumario: "Princípios e regras : uma distinção necessária -- O direito fundamental de liberdade -- Normas fundamentais reitoras da intervenção estatal no direito de liberdade -- O direito fundamental à individualização da medida cautelar pessoal -- Caracterísiticas das medidas cautelares pessoais -- A individualização da medida cautelar pessoal.",
            categorias: [processoPenal]
        )),
        ("fernandes", lexml(
            9, "Prisão cautelar", autor: "Fernandes, Patrícia Vieira dos Santos", ano: 2017,
            cddir: "341.4326",
            caminho: "DIREITO PÚBLICO > DIREITO PROCESSUAL > Direito Processual Penal > Partes. Ações > Detenção preventiva. Liberdade sob caução. Fiança. Liberdade provisória",
            sumario: "O princípio do estado de inocência na dogmática dos direitos fundamentais -- A prisão cautelar no processo penal brasileiro -- Novos paradigmas da prisão cautelar à luz do princípio do estado de inocência.",
            categorias: [processoPenal]
        )),
        ("maluf", lexml(
            10, "Terrorismo e prisão cautelar", autor: "Maluf, Elisa Leonesi", ano: 2016,
            cddir: "341.1366",
            caminho: "DIREITO PÚBLICO > DIREITO INTERNACIONAL PÚBLICO > Direito de Guerra. Leis de Guerra > Diversas espécies de guerra > Terrorismo",
            sumario: "Terrorismo : aspectos conceituais -- Terrorismo e prisão cautelar : tratamento normativo -- Terrorismo e prisão cautelar à luz da jurisprudência nacional e internacional -- Terrorismo e prisão cautelar : eficiência e garantismo.",
            categorias: []
        )),
        // LexML: constituição
        ("paula", lexml(
            11, "Poder constituinte", autor: "Paula, Fábio de", ano: 2016,
            cddir: "341.24", caminho: "DIREITO PÚBLICO > DIREITO CONSTITUCIONAL > Constituições",
            sumario: "O poder constituinte na sociedade moderna -- O discurso do poder constituinte e a validade do direito -- Poder constituinte e ação comunicativa.",
            categorias: [constitucional]
        )),
        ("borges", lexml(
            12, "Deus na Constituição brasileira", autor: "Borges, Donaldo de Assis", ano: 2016,
            cddir: "340", caminho: "DIREITO",
            sumario: "D. Adauto e as primeiras intervenções na área política -- A condenação à sociedade moderna -- A fé e o patriotismo a serviço da igreja -- A estratégia política pós-revolução de 1930 e a nova Constituição Federal de 1934.",
            categorias: [historia]
        )),
        ("sarlet", lexml(
            13, "Constituição e direito penal", autor: "Sarlet, Ingo Wolfgang", ano: 2016,
            cddir: "341.5", caminho: "DIREITO PÚBLICO > DIREITO PENAL",
            sumario: "Dignidade da pessoa humana e constitucionalização do sistema penal -- Liberdade de reunião e manifestação no horizonte do protesto social -- Tortura no prisma penal -- Algemas e Súmula vinculante no 11 -- Interrogatório e leis especiais, do início ao final da instrução -- Inviolabilidade de domicílio em caso de flagrante delito.",
            categorias: [constitucional]
        )),
        ("tannus", lexml(
            14, "Processo e Constituição", autor: "Tannus Neto, José Jorge", ano: 2017,
            cddir: "341.46", caminho: "DIREITO PÚBLICO > DIREITO PROCESSUAL > Direito Processual Civil",
            sumario: "Princípio da demanda -- Princípio da inafastabilidade da jurisdição -- Regra da primazia da decisão de mérito (justa e efetiva) -- Princípio da cooperação -- Princípio da igualdade processual -- Fim social e bem comum -- Princípio da fundamentação -- Outras premissas necessárias de um processo justo e efetivo.",
            categorias: []
        )),
        // LexML: trabalho
        ("supiot", lexml(
            15, "Crítica do direito do trabalho", autor: "Supiot, Alain", ano: 2016,
            cddir: "342.6", caminho: "DIREITO PRIVADO > DIREITO DO TRABALHO",
            sumario: "O trabalho em questões: Entre o contrato e estatuto : uma visão europeia da relação de trabalho -- O trabalho, objecto de direito -- A subordinação e a liberdade. A civilização da empresa -- O legal e o normal. As figuras da norma -- O futuro do trabalho. O trabalho do jurista.",
            categorias: [trabalho]
        )),
        ("mello", lexml(
            16, "Direito do trabalho para empresas", autor: "Mello, Alberto de Sá e", ano: 2016,
            cddir: "342.6", caminho: "DIREITO PRIVADO > DIREITO DO TRABALHO",
            sumario: "Formação e conteúdo típico do contrato individual de trabalho -- Redução e suspensão do contrato de trabalho. O lay-off -- Cessação do contrato de trabalho.",
            categorias: [trabalho]
        )),
        ("adamovich", lexml(
            17, "A equidade e o direito do trabalho", autor: "Adamovich, Eduardo Henrique Raymundo von", ano: 2017,
            cddir: "342.6", caminho: "DIREITO PRIVADO > DIREITO DO TRABALHO",
            sumario: "A equidade como princípio especializador do direito do trabalho -- O caráter equitativo da conciliação -- O papel da lei, do contrato e das demais fontes no direito e no processo do trabalho -- A prescrição, exceção material de raiz equitativa, no direito do trabalho.",
            categorias: [trabalho]
        )),
        ("luca", lexml(
            18, "Flexibilização do contrato de trabalho e crise econômica", autor: "Luca, Guilherme Domingos de", ano: 2017,
            cddir: "342.62", caminho: "DIREITO PRIVADO > DIREITO DO TRABALHO > Duração do Trabalho",
            sumario: "Do contrato de trabalho e a dignidade da pessoa humana na seara laboral -- Integração econômica e flexibilização -- Impacto tecnológico na flexibilização do direito do trabalho.",
            categorias: [trabalho]
        )),
        // LexML: civil
        ("espinola", lexml(
            19, "Os direitos reais limitados ou direitos sôbre a coisa alheia e os direitos reais de garantia no direito civil brasileiro",
            autor: "Espinola, Eduardo", ano: 1958,
            cddir: "342.12", caminho: "DIREITO PRIVADO > DIREITO CIVIL > Direitos reais. Coisas ou bens",
            sumario: "pt. 1 - Direitos reais limitados: Da enfiteuse. Das servidões prediais. Do usufruto. Do uso. Da habitação. Das rendas constituídas -- pt. 2 - Direitos reais de garantia: Disposições gerais. Do penhor. Da anticrese. Da hipoteca.",
            categorias: []
        )),
        ("carvalho-neto", lexml(
            20, "Extinção indireta das obrigações", autor: "Carvalho Neto, Inácio de", ano: 2003,
            cddir: "342.143",
            caminho: "DIREITO PRIVADO > DIREITO CIVIL > Obrigações. Contratos. Convenções > Extinção das obrigações",
            sumario: "Noções sobre obrigações -- Formas de extinção das obrigações -- Consignação -- Pagamento com sub-rogação -- Dação em pagamento -- Novação -- Compensação -- Transação -- Confusão -- Remissão -- Teoria geral da resolução.",
            categorias: []
        )),
        // A CDDir repetida é como o `/urn` devolve (defeito do leitor, anotado para a Fase 3).
        ("souza-neto", lexml(
            21, "Direito civil", autor: "Souza Neto, João Baptista de Mello e", ano: 2004,
            cddir: "342.1",
            caminho: "DIREITO PRIVADO > DIREITO CIVIL > Obrigações. Contratos. Convenções > DIREITO PRIVADO > DIREITO CIVIL",
            sumario: "Obrigações de dar, fazer e não fazer -- Das obrigações alternativas -- Obrigações divisíveis, indivisíveis e solidárias -- Cessão de crédito -- Do adimplemento e da extinção das obrigações -- Do pagamento em consignação -- Do pagamento com sub-rogação -- Imputação do pagamento -- Dação em pagamento -- Novação -- Da compensação -- Da confusão -- Da remissão",
            categorias: []
        )),
        ("mendes", lexml(
            22, "Inventários e partilhas", autor: "Mendes, Stela Maris Vieira", ano: 2017,
            cddir: "342.165",
            caminho: "DIREITO PRIVADO > DIREITO CIVIL > Direito de família > Direito hereditário ou das Sucessões",
            sumario: "Na capa: Herança -- Formas de sucessão -- Testamentos -- Arrolamento -- Imposto Causa Mortis -- Inventário extrajudicial -- Questões processuais -- Súmulas -- Enunciados IBDFAM Conselho da Justiça Federal.",
            categorias: [sucessoes]
        ))
    ]

    static let ids: [String: UUID] = Dictionary(uniqueKeysWithValues: fichas.map { ($0.chave, $0.livro.id) })

    static func motor() -> MotorDeBusca {
        MotorDeBusca(livros: fichas.map(\.livro), categorias: categorias)
    }

    // MARK: - Livros fotografados

    private static let lassale = Livro(
        id: uuid(1), estanteId: estante,
        titulo: "A essência da constituição",
        autores: ["Lassale, Ferdinand"],
        editora: "Liber Juris", local: "Rio de Janeiro", edicao: "2. ed.",
        serie: "Coleção estudos políticos constitucionais",
        ano: 1988,
        categoriaIds: [constitucional.id],
        // Só a 1ª página do sumário foi fotografada.
        itensSumario: [
            item(1, nil, "Nota explicativa", "ix"),
            item(1, nil, "Prefácio [Aurélio Wander Bastos]", "xi"),
            item(1, nil, "Introdução", "1"),
            item(1, "Capítulo I", "Sobre a Constituição", nil),
            item(2, nil, "O que é uma Constituição?", "5"),
            item(2, nil, "Lei e Constituição", "7"),
            item(2, nil, "Os fatores reais do poder", "11"),
            item(2, nil, "A monarquia", "12"),
            item(2, nil, "A aristocracia", "13"),
            item(2, nil, "A grande burguesia", "14"),
            item(2, nil, "Os banqueiros", "16"),
            item(2, nil, "A pequena burguesia e a classe operária", "18"),
            item(2, nil, "Os fatores reais do poder e as instituições jurídicas — a folha de papel", "19"),
            item(2, nil, "O sistema eleitoral das três classes", "20"),
            item(2, nil, "O senado", "22"),
            item(2, nil, "O Rei e o Exército", "22"),
            item(2, nil, "Poder organizado e poder inorgânico", "24")
        ]
    )

    private static let carvalhoSantosV24 = Livro(
        id: uuid(2), estanteId: estante,
        titulo: "Código civil brasileiro interpretado",
        subtitulo: "Principalmente do ponto de vista prático",
        autores: ["J. M. de Carvalho Santos"],
        editora: "Livraria Freitas Bastos", local: "Rio de Janeiro", edicao: "5.ª edição",
        volume: 24, volumeRotulo: "Volume XXIV", parte: "Direito das sucessões",
        artigosInicio: 1710, artigosFim: 1779,
        ano: 1956,
        categoriaIds: [sucessoes.id],
        itensSumario: [
            item(1, "Capítulo X", "Do direito de acrescer entre herdeiros e legatários", nil),
            item(2, "Art. 1.710", "Quando se verifique o direito de acrescer entre os co-herdeiros", "5"),
            item(2, "Art. 1.711", "Quando se considera feita a distribuição em partes ou quinhões pelo testador", "10"),
            item(2, "Art. 1.712", "Quinhão do herdeiro que falta. Como acresce à parte dos co-herdeiros conjuntos", "12"),
            item(2, "Art. 1.713", "Quota vaga, quando se transmite aos herdeiros legítimos", "16"),
            item(2, "Art. 1.714", "Obrigações e encargos que oneravam o quinhão do que deixou de herdar passam aos co-herdeiros a quem acrescer", "17"),
            item(2, "Art. 1.715", "Cota do que falta, quando não há direito de acrescer entre os co-legatários", "19"),
            item(2, "Art. 1.716", "Legado de usufruto e direito de acrescer", "21"),
            item(1, "Capítulo XI", "Da capacidade para adquirir por testamento", nil),
            item(2, "Art. 1.717", "Pessoas que podem adquirir por testamento", "33"),
            item(2, "Art. 1.718", "Pessoas incapazes absolutamente de receber por testamento", "43"),
            item(2, "Art. 1.719", "Pessoas que não podem ser nomeadas herdeiras nem legatárias", "47"),
            item(2, "Art. 1.720", "Nulidades das disposições em favor de incapazes", "67"),
            item(1, "Capítulo XII", "Dos herdeiros necessários", nil),
            item(2, "Art. 1.721", "Capacidade de disposição do testador que tenha descendente ou ascendente sucessível", "73"),
            item(2, "Art. 1.722", "Cálculo da metade disponível", "76"),
            item(2, "Art. 1.723", "Cláusulas de inalienabilidade, incomunicabilidade, etc., sôbre os bens testados", "84"),
            item(2, "Art. 1.724", "Herdeiro a quem o testador deixou algum legado, ou sua metade disponível, não perde direito à legítima", "121"),
            item(2, "Art. 1.725", "Como se excluem da sucessão o cônjuge e os parentes colaterais", "123"),
            item(1, "Capítulo XIII", "Da redução das disposições testamentárias", nil),
            item(2, "Art. 1.726", "Presunção quanto ao remanescente quando o testador só em parte dispôs da sua metade disponível", "125"),
            item(2, "Art. 1.727", "Modos de redução das disposições que excederem a metade disponível", "127"),
            item(2, "Art. 1.728", "Redução do legado consistente em prédio divisível", "134"),
            item(1, "Capítulo XIV", "Das substituições", nil),
            item(2, "Art. 1.729", "Faculdade de substituir o herdeiro ou legatário no caso em que não possa ou não queira aceitar a deixa", "137"),
            item(2, "Art. 1.730", "Substituição de muitas pessoas a uma só e vice-versa", "145"),
            item(2, "Art. 1.731", "Substituto fica sujeito às condições e encargos impostos ao substituído", "147"),
            item(2, "Art. 1.732", "Proporção dos quinhões, no caso de substituição recíproca", "149"),
            item(2, "Art. 1.733", "Fideicomisso", "151"),
            item(2, "Art. 1.734", "Caráter da propriedade do fiduciário", "194"),
            item(2, "Art. 1.735", "Renúncia do fideicomissário. Efeitos", "201"),
            item(2, "Art. 1.736", "Direito do fideicomissário à parte que acrescer ao fiduciário", "208"),
            item(2, "Art. 1.737", "Responsabilidade do fideicomissário pelos encargos que restarem quando vier à sucessão", "210"),
            item(2, "Art. 1.738", "Casos de caducidade do fideicomisso. Efeitos da caducidade", "212"),
            item(2, "Art. 1.739", "Nulidade dos fideicomissos além do segundo grau", "217"),
            item(2, "Art. 1.740", "A nulidade da substituição ilegal não prejudica a instituição", "219")
        ]
    )

    private static let tratadoT48 = Livro(
        id: uuid(3), estanteId: estante,
        titulo: "Tratado de direito privado",
        subtitulo: "Direito das Obrigações: Contrato coletivo do trabalho. Contratos especiais de trabalho. Preposição comercial. Ações. Acôrdos em dissídios coletivos e individuais. Contrato de trabalho rural.",
        autores: ["Pontes de Miranda"],
        editora: "Editor Borsoi", local: "Rio de Janeiro", edicao: "3.ª edição, reimpressão",
        volume: 48, volumeRotulo: "Tomo XLVIII", parte: "Parte especial",
        ano: 1972,
        categoriaIds: [trabalho.id],
        // Os subitens numerados de cada § são filhos (nível + 1) com a página do §.
        itensSumario: Array([
            [
                item(1, "Parte IV", "Contrato coletivo de trabalho", nil),
                item(2, "Capítulo I", "Conceito e natureza do contrato coletivo de trabalho", nil)
            ],
            paragrafo("§ 5.108", "Conceito e natureza do contrato coletivo de trabalho", "3", [
                "Conceito", "Figurantes coletivos", "Contrato normativo de trabalho", "Acôrdo de emprêsa"
            ]),
            paragrafo("§ 5.109", "Natureza do contrato coletivo de trabalho, normativo ou não", "17", [
                "Precisões", "Contrato coletivo e normativo de trabalho", "Teorias",
                "Contrato coletivo de trabalho e falta de tal contrato", "Acôrdos coletivos de trabalho",
                "Comissões internas", "Acôrdos econômicos coletivos"
            ]),
            [item(2, "Capítulo II", "Pressupostos do contrato coletivo de trabalho", nil)],
            paragrafo("§ 5.110", "Figurantes do contrato coletivo de trabalho", "25", [
                "Contrato coletivo de trabalho, simples, ou normativo, ou duplo", "Teorias",
                "Presentação e representação", "Contrato coletivo de trabalho e coercividade"
            ]),
            paragrafo("§ 5.111", "Pressupostos de fundo (pessoais e contenutísticos) para os contratos coletivos de trabalho", "32", [
                "Conteúdo previsto em lei", "Cláusulas contratuais", "Começo de eficácia e começo de aplicabilidade",
                "Interpretação do contrato coletivo de trabalho", "Adesões"
            ]),
            paragrafo("§ 5.112", "Pressupostos formais", "46", ["Forma", "Homologação", "Registo", "Publicidade"]),
            [item(2, "Capítulo III", "Validade do contrato coletivo de trabalho", nil)],
            paragrafo("§ 5.113", "Validade e invalidade", "53", [
                "Causas de nulidade e de anulabilidade", "Objeto ilícito e objeto impossível",
                "Normatividade ocorrente", "Infração de regras jurídicas cogentes"
            ]),
            [
                item(1, "Parte VII", "Ações do direito do trabalho e acôrdos em dissídios coletivos e individuais", nil),
                item(2, "Capítulo I", "Ações do direito do trabalho", nil)
            ],
            paragrafo("§ 5.151", "Ações, no sentido do direito material", "251", [
                "Precisões", "Legitimação jurídica pré-processual e processual"
            ]),
            paragrafo("§ 5.152", "Ações do direito do trabalho", "252", [
                "Ação de anotação da carteira profissional", "Ação declaratória da relação jurídica de trabalho",
                "Ação declaratória da estabilidade (dita ação de reconhecimento da estabilidade)",
                "Ação de denúncia cheia exercida pelo empregado", "Ações constitutivas negativas, no direito do trabalho",
                "Ação indenizatória do empregado", "Ação sôbre transferência ilegítima",
                "Ação declaratória exercida pelo empregador", "Ação condenatória de reintegração ou de readmissão no emprêgo",
                "Ações possessórias do empregado", "Ações de equiparação", "Ações contra alteração do contrato de trabalho",
                "Ações coletivas de direito de trabalho", "Ação de observância da decisão em ação coletiva",
                "Ação rescisória de sentença", "Ações executivas"
            ]),
            [item(2, "Capítulo II", "Acôrdos em dissídios coletivos e individuais entre empregados e empregadores", nil)],
            paragrafo("§ 5.153", "Dissídios coletivos", "281", [
                "Título executivo extrajudicial", "Objeções", "Ação de cumprimento e ação de execução", "Conciliação"
            ]),
            paragrafo("§ 5.154", "Dissídios individuais e dissídios coletivos", "285", [
                "Precisões", "Espécies de dissídios", "Lei ordinária especificadora da competência da Justiça do trabalho",
                "Dissídios individuais", "Dissídios coletivos"
            ]),
            paragrafo("§ 5.155", "Os acôrdos nas duas espécies de dissídios", "306", [
                "Elementos distintivos", "Elementos comuns e função judicial", "Cumprimento dos acôrdos", "Revisão"
            ]),
            paragrafo("§ 5.156", "Execução dos acôrdos", "310", ["Dívida líquida e dívida ilíquida", "Ação executiva"]),
            paragrafo("§ 5.157", "Acôrdos extraprocessuais", "317", [
                "Precisões conceptuais", "Acôrdos extraprocessuais interempresariais"
            ]),
            [item(2, "Capítulo III", "Natureza da decisão judicial normativa", nil)],
            paragrafo("§ 5.158", "Função de elaborar normas de trabalho", "319", [
                "Duplo problema", "Lei que aponta casos de competência", "Natureza da decisão judicial normativa"
            ]),
            paragrafo("§ 5.159", "Considerações finais", "327", [
                "Técnica legislativa", "Justiça do Trabalho e contratos coletivos"
            ])
        ].joined())
    )

    /// Só a folha de rosto foi fotografada: sem sumário.
    private static let tratadoT1 = Livro(
        id: uuid(4), estanteId: estante,
        titulo: "Tratado de direito privado",
        subtitulo: "Introdução. Pessoas físicas e jurídicas",
        autores: ["Pontes de Miranda"],
        editora: "Editor Borsoi", local: "Rio de Janeiro",
        volume: 1, volumeRotulo: "Tomo I", parte: "Parte geral",
        ano: 1954
    )

    // MARK: - Montagem

    private static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    private static func item(_ nivel: Int, _ numeracao: String?, _ titulo: String, _ pagina: String?) -> ItemSumario {
        ItemSumario(nivel: nivel, numeracao: numeracao, titulo: titulo, pagina: pagina, origem: .foto)
    }

    /// Um § do Tratado (nível 3) e os seus subitens numerados (nível 4), todos com a página do §.
    private static func paragrafo(_ numeracao: String, _ titulo: String, _ pagina: String, _ subitens: [String]) -> [ItemSumario] {
        [item(3, numeracao, titulo, pagina)]
            + subitens.enumerated().map { item(4, "\($0.offset + 1).", $0.element, pagina) }
    }

    /// Ficha do LexML: o sumário vem como na `descricao` (itens separados por " -- ") e a CDDir como
    /// o caminho da ficha `/urn` (níveis separados por " > ").
    private static func lexml(
        _ numero: Int,
        _ titulo: String,
        autor: String,
        ano: Int,
        cddir: String,
        caminho: String,
        sumario: String,
        categorias: [Categoria]
    ) -> Livro {
        Livro(
            id: uuid(numero), estanteId: estante,
            titulo: titulo,
            autores: [autor],
            ano: ano,
            cddir: cddir,
            cddirCaminho: caminho.components(separatedBy: " > "),
            origem: .lexml,
            categoriaIds: Set(categorias.map(\.id)),
            itensSumario: sumario.components(separatedBy: " -- ").map {
                ItemSumario(nivel: 1, titulo: $0, origem: .lexml)
            }
        )
    }
}
