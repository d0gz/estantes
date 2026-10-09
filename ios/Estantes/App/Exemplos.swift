#if DEBUG
import SwiftUI

/// Dados de exemplo para previews e capturas do simulador. Só existe em DEBUG: o app de verdade nunca os vê.
///
/// Fica em `App/` (e não na Apresentação) porque monta um repositório concreto (Core Data em memória):
/// escolher implementação é papel da montagem. Os previews das telas usam `ComExemplos` daqui.
enum DadosDeExemplo {
    /// Biblioteca pequena, com livros reais de direito, para as telas terem conteúdo plausível.
    static func preencher(_ repositorio: BibliotecaRepositorio) async throws {
        let escritorio = Estante(nome: "Escritório")
        let sala = Estante(nome: "Sala")
        let tratados = Estante(nome: "Tratados")
        for estante in [escritorio, sala, tratados] {
            try await repositorio.salvar(estante)
        }

        let livros = [
            Livro(estanteId: escritorio.id, titulo: "Curso de direito constitucional positivo",
                  autores: ["Silva, José Afonso da"], editora: "Malheiros", ano: 2014, prateleira: "1ª de cima"),
            Livro(estanteId: escritorio.id, titulo: "Direitos fundamentais e processo penal",
                  autores: ["Fernandes, Antonio Scarance"], ano: 2010, prateleira: "1ª de cima"),
            Livro(estanteId: escritorio.id, titulo: "Curso de direito civil brasileiro",
                  autores: ["Diniz, Maria Helena"], editora: "Saraiva", ano: 2012, prateleira: "2ª de cima"),
            Livro(estanteId: sala.id, titulo: "Teoria pura do direito",
                  autores: ["Kelsen, Hans"], editora: "Martins Fontes", ano: 1998),
            Livro(estanteId: tratados.id, titulo: "Tratado de direito privado",
                  autores: ["Miranda, Pontes de"], editora: "Borsoi", local: "Rio de Janeiro",
                  volume: 48, volumeRotulo: "Tomo XLVIII", ano: 1965, prateleira: "caixa azul"),
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

    /// Argumentos `-chave valor` viram entradas do `UserDefaults` (domínio de argumentos), sem parser próprio.
    static var pedida: Captura? {
        UserDefaults.standard.string(forKey: "captura").flatMap(Captura.init(rawValue:))
    }

    @MainActor @ViewBuilder
    var tela: some View {
        switch self {
        case .inicio:
            ComExemplos { InicioView(viewModel: $0.fazerInicioViewModel()) }
        case .inicioVazio:
            ComExemplos(vazio: true) { InicioView(viewModel: $0.fazerInicioViewModel()) }
        case .inicioNovaEstante:
            ComExemplos { InicioView(viewModel: $0.fazerInicioViewModel(), acaoInicial: .novaEstante) }
        case .apagarEstante:
            ComExemplos { InicioView(viewModel: $0.fazerInicioViewModel(), acaoInicial: .apagar(nomeDaEstante: "Escritório")) }
        case .apagarEstanteMover:
            ComExemplos {
                InicioView(viewModel: $0.fazerInicioViewModel(), acaoInicial: .escolherDestino(nomeDaEstante: "Escritório"))
            }
        }
    }
}
#endif
