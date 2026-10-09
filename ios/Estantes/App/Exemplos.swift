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

    /// Biblioteca pequena, com livros reais de direito, para as telas terem conteúdo plausível:
    /// duas prateleiras numeradas, dois tomos da mesma obra, um livro sem prateleira e uma estante vazia.
    static func preencher(_ repositorio: BibliotecaRepositorio) async throws {
        for estante in [escritorio, sala, quarto] {
            try await repositorio.salvar(estante)
        }

        let livros = [
            Livro(estanteId: escritorio.id, titulo: "Curso de direito constitucional positivo",
                  autores: ["Silva, José Afonso da"], editora: "Malheiros", ano: 2014, prateleira: "1ª de cima"),
            Livro(estanteId: escritorio.id, titulo: "Direitos fundamentais e processo penal",
                  autores: ["Fernandes, Antonio Scarance"], ano: 2010, prateleira: "1ª de cima"),
            Livro(estanteId: escritorio.id, titulo: "Curso de direito civil brasileiro",
                  autores: ["Diniz, Maria Helena"], editora: "Saraiva", ano: 2012, prateleira: "2ª de cima"),
            Livro(id: tratadoTomo48, estanteId: escritorio.id, titulo: "Tratado de direito privado",
                  autores: ["Miranda, Pontes de"], editora: "Borsoi", local: "Rio de Janeiro", edicao: "2.ª ed.",
                  volume: 48, volumeRotulo: "Tomo XLVIII", parte: "Parte especial", ano: 1965, prateleira: "caixa azul"),
            Livro(estanteId: escritorio.id, titulo: "Tratado de direito privado",
                  autores: ["Miranda, Pontes de"], editora: "Borsoi", local: "Rio de Janeiro",
                  volume: 47, volumeRotulo: "Tomo XLVII", parte: "Parte especial", ano: 1965, prateleira: "caixa azul"),
            Livro(estanteId: escritorio.id, titulo: "Lições preliminares de direito",
                  autores: ["Reale, Miguel"], editora: "Saraiva", ano: 2002),
            Livro(estanteId: sala.id, titulo: "Teoria pura do direito",
                  autores: ["Kelsen, Hans"], editora: "Martins Fontes", ano: 1998),
        ]
        for livro in livros {
            try await repositorio.salvar(livro)
        }
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
    case apagarLivro = "ApagarLivro"

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
        case .apagarLivro:
            ComExemplos {
                NavegacaoView(
                    dependencias: $0,
                    caminhoInicial: Self.caminho(DadosDeExemplo.escritorio, livro: DadosDeExemplo.tratadoTomo48),
                    abrirConfirmacaoDoLivro: true
                )
            }
        }
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
