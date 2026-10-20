#if DEBUG
import SwiftUI

/// Dados de exemplo para previews e capturas do simulador. Só existe em DEBUG: o app de verdade nunca os vê.
///
/// Fica em `App/` (e não na Apresentação) porque monta um repositório concreto (Core Data em memória):
/// escolher implementação é papel da montagem. Os previews das telas usam `ComExemplos` daqui.
enum DadosDeExemplo {
    // Ids e datas fixos: as capturas abrem a pilha direto numa estante ou num livro.
    static let escritorio = Estante(
        id: UUID(uuidString: "E0000000-0000-0000-0000-000000000001")!, nome: "Escritório",
        criadaEm: Date(timeIntervalSinceReferenceDate: 1)
    )
    static let sala = Estante(
        id: UUID(uuidString: "E0000000-0000-0000-0000-000000000002")!, nome: "Sala",
        criadaEm: Date(timeIntervalSinceReferenceDate: 2)
    )
    static let quarto = Estante(
        id: UUID(uuidString: "E0000000-0000-0000-0000-000000000003")!, nome: "Quarto",
        criadaEm: Date(timeIntervalSinceReferenceDate: 3)
    )
    static let tratadoTomo48 = UUID(uuidString: "B0000000-0000-0000-0000-000000000048")!
    /// Sem categoria: o chip fantasma no Detalhe e na Estante.
    static let tratadoTomo47 = UUID(uuidString: "B0000000-0000-0000-0000-000000000047")!
    static let cursoConstitucional = UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!
    /// Três autores e dois de nome longo, para o Detalhe: sobrenomes no cabeçalho, nomes inteiros no cartão "Autores".
    static let teoriaGeralDoProcesso = UUID(uuidString: "B0000000-0000-0000-0000-000000000003")!
    static let cursoMendesBranco = UUID(uuidString: "B0000000-0000-0000-0000-000000000002")!
    /// Com colaborador (prefácio), como na ficha CIP real.
    static let essenciaDaConstituicao = UUID(uuidString: "B0000000-0000-0000-0000-000000000004")!

    // Categorias: cores variadas, uma sem livros ("Ler depois") e livros com zero, uma e duas categorias.
    static let constitucional = Categoria(nome: "Constitucional", cor: .vermelho)
    static let processo = Categoria(nome: "Processo", cor: .verde)
    static let civil = Categoria(nome: "Civil", cor: .laranja)
    static let filosofia = Categoria(nome: "Filosofia", cor: .marrom)
    static let lerDepois = Categoria(nome: "Ler depois", cor: .cinza)

    /// Biblioteca pequena, com livros reais de direito, para as telas terem conteúdo plausível:
    /// duas prateleiras numeradas, dois tomos da mesma obra, um livro sem prateleira e uma estante vazia.
    static func preencher(_ repositorio: BibliotecaRepositorio) async throws {
        for estante in [escritorio, sala, quarto] {
            try await repositorio.salvar(estante)
        }
        for categoria in [constitucional, processo, civil, filosofia, lerDepois] {
            try await repositorio.salvar(categoria)
        }

        let livros = [
            Livro(id: cursoConstitucional, estanteId: escritorio.id, titulo: "Curso de direito constitucional positivo",
                  autores: ["Silva, José Afonso da"], editora: "Malheiros", ano: 2014, prateleira: "1ª de cima",
                  categoriaIds: [constitucional.id]),
            Livro(estanteId: escritorio.id, titulo: "Direitos fundamentais e processo penal",
                  autores: ["Fernandes, Antonio Scarance"], ano: 2010, prateleira: "1ª de cima",
                  categoriaIds: [constitucional.id, processo.id]),
            Livro(estanteId: escritorio.id, titulo: "Curso de direito civil brasileiro",
                  autores: ["Diniz, Maria Helena"], editora: "Saraiva", ano: 2012, prateleira: "2ª de cima",
                  categoriaIds: [civil.id]),
            Livro(id: tratadoTomo48, estanteId: escritorio.id, titulo: "Tratado de direito privado",
                  subtitulo: "Direito das obrigações: Contrato coletivo do trabalho. Contratos especiais de trabalho",
                  autores: ["Miranda, Pontes de"], editora: "Borsoi", local: "Rio de Janeiro", edicao: "2.ª ed.",
                  volume: 48, volumeRotulo: "Tomo XLVIII", parte: "Parte especial", ano: 1965, prateleira: "caixa azul",
                  categoriaIds: [civil.id], itensSumario: sumarioDoTomo48),
            Livro(id: tratadoTomo47, estanteId: escritorio.id, titulo: "Tratado de direito privado",
                  autores: ["Miranda, Pontes de"], editora: "Borsoi", local: "Rio de Janeiro",
                  volume: 47, volumeRotulo: "Tomo XLVII", parte: "Parte especial", ano: 1965, prateleira: "caixa azul"),
            Livro(estanteId: escritorio.id, titulo: "Lições preliminares de direito",
                  autores: ["Reale, Miguel"], editora: "Saraiva", ano: 2002),
            Livro(estanteId: sala.id, titulo: "Teoria pura do direito",
                  autores: ["Kelsen, Hans"], editora: "Martins Fontes", ano: 1998, categoriaIds: [filosofia.id]),
            Livro(id: teoriaGeralDoProcesso, estanteId: sala.id, titulo: "Teoria geral do processo",
                  autores: ["Cintra, Antonio Carlos de Araújo", "Grinover, Ada Pellegrini", "Dinamarco, Cândido Rangel"],
                  editora: "Malheiros", local: "São Paulo", edicao: "26.ª ed.", ano: 2010, categoriaIds: [processo.id]),
            Livro(id: cursoMendesBranco, estanteId: sala.id, titulo: "Curso de direito constitucional",
                  autores: ["Mendes, Gilmar Ferreira", "Branco, Paulo Gustavo Gonet"],
                  editora: "Saraiva", local: "São Paulo", edicao: "7.ª ed.", ano: 2012, categoriaIds: [constitucional.id]),
            Livro(id: essenciaDaConstituicao, estanteId: sala.id, titulo: "A essência da constituição",
                  autores: ["Lassale, Ferdinand"],
                  colaboradores: [Colaborador(nome: "Bastos, Aurélio Wander", papel: "prefácio")],
                  editora: "Liber Juris", local: "Rio de Janeiro", edicao: "2.ª ed.",
                  serie: "Coleção estudos políticos constitucionais", ano: 1988, categoriaIds: [constitucional.id]),
        ]
        for livro in livros {
            try await repositorio.salvar(livro)
        }
        // Duas fotos da miniatura, uma de cada tipo; os outros livros ficam com a substituta.
        try await repositorio.salvarFotoMiniatura(
            fotoDeExemplo(fundo: UIColor(red: 0.55, green: 0.12, blue: 0.14, alpha: 1), texto: .white,
                          linhas: ["JOSÉ AFONSO DA SILVA", "", "CURSO DE", "DIREITO", "CONSTITUCIONAL", "POSITIVO"]),
            doLivro: cursoConstitucional
        )
        try await repositorio.salvarFotoMiniatura(
            fotoDeExemplo(fundo: UIColor(red: 0.96, green: 0.93, blue: 0.85, alpha: 1), texto: .black,
                          linhas: ["PONTES DE MIRANDA", "", "TRATADO DE", "DIREITO PRIVADO", "", "TOMO XLVIII", "", "BORSOI"]),
            doLivro: tratadoTomo48
        )
    }

    /// Sumário no formato do contrato de campos (PLANO): pré-textual em romanos, divisões sem página, § com a
    /// numeração separada e subitens numerados como filhos na mesma página. Mais de 10 itens: o Detalhe mostra
    /// "Ver sumário completo". Texto ilustrativo, não transcrito do livro.
    private static let sumarioDoTomo48: [ItemSumario] = [
        ItemSumario(nivel: 1, titulo: "Nota explicativa", pagina: "ix"),
        ItemSumario(nivel: 1, numeracao: "Título LIII", titulo: "Contrato coletivo de trabalho"),
        ItemSumario(nivel: 2, numeracao: "Capítulo I", titulo: "Conceito e natureza"),
        ItemSumario(nivel: 3, numeracao: "§ 5.108", titulo: "Conceito e natureza do contrato coletivo", pagina: "3"),
        ItemSumario(nivel: 4, numeracao: "1.", titulo: "Conceito", pagina: "3"),
        ItemSumario(nivel: 4, numeracao: "2.", titulo: "Figurantes coletivos", pagina: "3"),
        ItemSumario(nivel: 3, numeracao: "§ 5.109", titulo: "Pressupostos e requisitos", pagina: "12"),
        ItemSumario(nivel: 3, numeracao: "§ 5.110", titulo: "Eficácia do contrato coletivo", pagina: "21"),
        ItemSumario(nivel: 2, numeracao: "Capítulo II", titulo: "Conteúdo e interpretação"),
        ItemSumario(nivel: 3, numeracao: "§ 5.111", titulo: "Cláusulas obrigacionais", pagina: "34"),
        ItemSumario(nivel: 3, numeracao: "§ 5.112", titulo: "Cláusulas normativas", pagina: "41"),
        ItemSumario(nivel: 3, numeracao: "§ 5.113", titulo: "Interpretação", pagina: "52"),
        ItemSumario(nivel: 1, numeracao: "Título LIV", titulo: "Contratos especiais de trabalho"),
        ItemSumario(nivel: 2, numeracao: "§ 5.114", titulo: "Contrato de aprendizagem", pagina: "67"),
    ]

    /// Foto desenhada (capa ou folha de rosto fictícia), em JPEG como viria da câmera. Sem fotos reais de livros:
    /// direitos autorais (mesma regra das fotos do conjunto de avaliação).
    private static func fotoDeExemplo(fundo: UIColor, texto: UIColor, linhas: [String]) -> Data {
        let tamanho = CGSize(width: 600, height: 900)
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        let imagem = UIGraphicsImageRenderer(size: tamanho, format: formato).image { contexto in
            fundo.setFill()
            contexto.fill(CGRect(origin: .zero, size: tamanho))
            let paragrafo = NSMutableParagraphStyle()
            paragrafo.alignment = .center
            let atributos: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Georgia-Bold", size: 52) ?? UIFont.boldSystemFont(ofSize: 52),
                .foregroundColor: texto,
                .paragraphStyle: paragrafo,
            ]
            (linhas.joined(separator: "\n") as NSString)
                .draw(in: CGRect(x: 30, y: 150, width: 540, height: 700), withAttributes: atributos)
        }
        return imagem.jpegData(compressionQuality: 0.8)!
    }
}

/// Mostra o conteúdo só depois de montar um banco em memória (vazio ou com os exemplos).
/// Necessário porque preencher o banco é assíncrono: sem esperar, a tela carregaria antes dos dados.
struct ComExemplos<Conteudo: View>: View {
    var vazio = false
    /// `@MainActor`: o closure cria ViewModels, que são isolados na fila principal.
    let conteudo: @MainActor (Dependencias) -> Conteudo

    @State private var dependencias: Dependencias?
    @State private var falha: String?

    var body: some View {
        Group {
            if let dependencias = dependencias {
                conteudo(dependencias)
            } else if let falha = falha {
                Text(falha)
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                let montadas = try Dependencias.emMemoria()
                if !vazio {
                    try await DadosDeExemplo.preencher(montadas.repositorio)
                }
                dependencias = montadas
            } catch {
                falha = "Falha ao montar os exemplos: \(error)"
            }
        }
    }
}

/// Telas que podem ser abertas direto pelo argumento de lançamento `-captura <Tela>`
/// (`xcrun simctl launch <aparelho> com.ricardo.estantes -captura Inicio`). O `simctl` não toca na tela,
/// então é assim que a captura chega às telas internas, sempre com os mesmos dados de exemplo.
enum Captura: String {
    case inicio = "Inicio"
    case inicioVazio = "InicioVazio"
    case inicioNovaEstante = "InicioNovaEstante"
    case apagarEstante = "ApagarEstante"
    case apagarEstanteMover = "ApagarEstanteMover"
    case estante = "Estante"
    case estanteVazia = "EstanteVazia"
    case livroDetalhe = "LivroDetalhe"
    case livroDetalheTresAutores = "LivroDetalheTresAutores"
    case livroDetalheDoisAutores = "LivroDetalheDoisAutores"
    case livroDetalheColaborador = "LivroDetalheColaborador"
    case apagarLivro = "ApagarLivro"
    case livroDetalheSemCategoria = "LivroDetalheSemCategoria"
    case escolhaDeCategorias = "EscolhaDeCategorias"
    case editarSumario = "EditarSumario"
    case editarSumarioVazio = "EditarSumarioVazio"
    case formularioNovo = "FormularioNovo"
    case formularioEditar = "FormularioEditar"
    case formularioColaborador = "FormularioColaborador"
    case categorias = "Categorias"
    case categoriasVazia = "CategoriasVazia"
    case categoriaNova = "CategoriaNova"
    case categoriaEditar = "CategoriaEditar"
    case apagarCategoria = "ApagarCategoria"
    case estilo = "Estilo"
    case estiloTelas = "EstiloTelas"
    case estiloCategorias = "EstiloCategorias"

    /// Argumentos `-chave valor` viram entradas do `UserDefaults` (domínio de argumentos), sem parser próprio.
    static var pedida: Captura? {
        UserDefaults.standard.string(forKey: "captura").flatMap(Captura.init(rawValue:))
    }

    @MainActor @ViewBuilder
    var tela: some View {
        switch self {
        case .inicio:
            ComExemplos { NavegacaoView(dependencias: $0) }
        case .inicioVazio:
            ComExemplos(vazio: true) { NavegacaoView(dependencias: $0) }
        case .inicioNovaEstante:
            ComExemplos { NavegacaoView(dependencias: $0, acaoInicial: .novaEstante) }
        case .apagarEstante:
            ComExemplos { NavegacaoView(dependencias: $0, acaoInicial: .apagar(nomeDaEstante: "Escritório")) }
        case .apagarEstanteMover:
            ComExemplos { NavegacaoView(dependencias: $0, acaoInicial: .escolherDestino(nomeDaEstante: "Escritório")) }
        case .estante:
            ComExemplos { NavegacaoView(dependencias: $0, caminhoInicial: Self.caminho(DadosDeExemplo.escritorio)) }
        case .estanteVazia:
            ComExemplos { NavegacaoView(dependencias: $0, caminhoInicial: Self.caminho(DadosDeExemplo.quarto)) }
        case .livroDetalhe:
            ComExemplos {
                NavegacaoView(dependencias: $0, caminhoInicial: Self.caminho(DadosDeExemplo.escritorio, livro: DadosDeExemplo.tratadoTomo48))
            }
        case .livroDetalheTresAutores:
            ComExemplos {
                NavegacaoView(dependencias: $0, caminhoInicial: Self.caminho(DadosDeExemplo.sala, livro: DadosDeExemplo.teoriaGeralDoProcesso))
            }
        case .livroDetalheDoisAutores:
            ComExemplos {
                NavegacaoView(dependencias: $0, caminhoInicial: Self.caminho(DadosDeExemplo.sala, livro: DadosDeExemplo.cursoMendesBranco))
            }
        case .livroDetalheColaborador:
            ComExemplos {
                NavegacaoView(dependencias: $0, caminhoInicial: Self.caminho(DadosDeExemplo.sala, livro: DadosDeExemplo.essenciaDaConstituicao))
            }
        case .livroDetalheSemCategoria:
            ComExemplos {
                NavegacaoView(dependencias: $0, caminhoInicial: Self.caminho(DadosDeExemplo.escritorio, livro: DadosDeExemplo.tratadoTomo47))
            }
        case .escolhaDeCategorias:
            ComExemplos {
                NavegacaoView(
                    dependencias: $0,
                    caminhoInicial: Self.caminho(DadosDeExemplo.escritorio, livro: DadosDeExemplo.tratadoTomo48),
                    folhaInicial: FolhaPendente(.categorias, em: RotaDoLivro(livroId: DadosDeExemplo.tratadoTomo48))
                )
            }
        case .editarSumario:
            ComExemplos {
                NavegacaoView(
                    dependencias: $0,
                    caminhoInicial: Self.caminho(DadosDeExemplo.escritorio, livro: DadosDeExemplo.tratadoTomo48),
                    folhaInicial: FolhaPendente(.sumario, em: RotaDoLivro(livroId: DadosDeExemplo.tratadoTomo48))
                )
            }
        case .editarSumarioVazio:
            ComExemplos {
                NavegacaoView(
                    dependencias: $0,
                    caminhoInicial: Self.caminho(DadosDeExemplo.escritorio, livro: DadosDeExemplo.tratadoTomo47),
                    folhaInicial: FolhaPendente(.sumario, em: RotaDoLivro(livroId: DadosDeExemplo.tratadoTomo47))
                )
            }
        case .apagarLivro:
            ComExemplos {
                NavegacaoView(
                    dependencias: $0,
                    caminhoInicial: Self.caminho(DadosDeExemplo.escritorio, livro: DadosDeExemplo.tratadoTomo48),
                    folhaInicial: FolhaPendente(.confirmacaoDeApagar, em: RotaDoLivro(livroId: DadosDeExemplo.tratadoTomo48))
                )
            }
        // O formulário abre na folha de verdade, sobre a estante ou o detalhe: assim "Cancelar" e "Salvar"
        // fecham a folha também quando o app fica aberto depois da captura (como raiz, não haveria o que fechar).
        case .formularioNovo:
            ComExemplos {
                NavegacaoView(
                    dependencias: $0,
                    caminhoInicial: Self.caminho(DadosDeExemplo.escritorio),
                    folhaInicial: FolhaPendente(.formulario, em: DadosDeExemplo.escritorio)
                )
            }
        case .formularioEditar:
            ComExemplos {
                NavegacaoView(
                    dependencias: $0,
                    caminhoInicial: Self.caminho(DadosDeExemplo.escritorio, livro: DadosDeExemplo.tratadoTomo48),
                    folhaInicial: FolhaPendente(.formulario, em: RotaDoLivro(livroId: DadosDeExemplo.tratadoTomo48))
                )
            }
        case .formularioColaborador:
            ComExemplos {
                NavegacaoView(
                    dependencias: $0,
                    caminhoInicial: Self.caminho(DadosDeExemplo.sala, livro: DadosDeExemplo.essenciaDaConstituicao),
                    folhaInicial: FolhaPendente(.formulario, em: RotaDoLivro(livroId: DadosDeExemplo.essenciaDaConstituicao))
                )
            }
        case .categorias:
            ComExemplos { NavegacaoView(dependencias: $0, caminhoInicial: Self.caminhoDasCategorias) }
        case .categoriasVazia:
            ComExemplos(vazio: true) { NavegacaoView(dependencias: $0, caminhoInicial: Self.caminhoDasCategorias) }
        case .categoriaNova:
            ComExemplos { NavegacaoView(dependencias: $0, acaoNasCategorias: .nova, caminhoInicial: Self.caminhoDasCategorias) }
        case .categoriaEditar:
            ComExemplos {
                NavegacaoView(
                    dependencias: $0, acaoNasCategorias: .editar(nomeDaCategoria: "Constitucional"),
                    caminhoInicial: Self.caminhoDasCategorias
                )
            }
        case .apagarCategoria:
            ComExemplos {
                NavegacaoView(
                    dependencias: $0, acaoNasCategorias: .apagar(nomeDaCategoria: "Constitucional"),
                    caminhoInicial: Self.caminhoDasCategorias
                )
            }
        case .estilo:
            CatalogoDeEstiloView(pagina: .fundamentos)
        case .estiloTelas:
            CatalogoDeEstiloView(pagina: .telas)
        case .estiloCategorias:
            CatalogoDeEstiloView(pagina: .categorias)
        }
    }

    private static var caminhoDasCategorias: NavigationPath {
        var caminho = NavigationPath()
        caminho.append(RotaDasCategorias())
        return caminho
    }

    private static func caminho(_ estante: Estante, livro: UUID? = nil) -> NavigationPath {
        var caminho = NavigationPath()
        caminho.append(estante)
        if let livro = livro {
            caminho.append(RotaDoLivro(livroId: livro))
        }
        return caminho
    }
}
#endif
