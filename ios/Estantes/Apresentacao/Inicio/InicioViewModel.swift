import Foundation

/// Uma estante como a tela inicial a mostra: a estante e quantos livros ela tem.
/// Mora na Apresentação porque a contagem é um dado da tela, não uma propriedade da `Estante`.
struct EstanteResumo: Identifiable, Equatable {
    let estante: Estante
    let quantidadeDeLivros: Int

    var id: UUID { estante.id }
}

/// Estado da tela inicial e as ações sobre as estantes.
///
/// Sem `@FetchRequest`: depois de cada gravação o ViewModel relê tudo do repositório, então a tela
/// é sempre derivada do banco, nunca de uma cópia editada à mão.
@MainActor
final class InicioViewModel: ObservableObject {
    /// Um `enum` em vez de vários `Bool`: combinações impossíveis ("carregando" e "erro" ao mesmo tempo)
    /// nem podem ser escritas.
    enum Estado: Equatable {
        case carregando
        case vazio
        case pronto([EstanteResumo])
        case erro(String)
    }

    @Published private(set) var estado: Estado = .carregando
    /// Falha ao gravar. Fica separada do `estado`: a lista continua na tela e um alerta avisa.
    @Published var mensagemDeErro: String?

    private let repositorio: BibliotecaRepositorio

    init(repositorio: BibliotecaRepositorio) {
        self.repositorio = repositorio
    }

    /// Nome aparado, ou `nil` se só tiver espaços (aí criar e renomear não fazem nada).
    static func nomeValido(_ texto: String) -> String? {
        let aparado = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        return aparado.isEmpty ? nil : aparado
    }

    func carregar() async {
        do {
            var resumos: [EstanteResumo] = []
            // Uma contagem por estante: são poucas estantes, e a contagem é feita no SQLite (COUNT),
            // sem carregar livros. Uma consulta agregada só valeria com centenas de estantes.
            for estante in try await repositorio.estantes() {
                let quantidade = try await repositorio.quantidadeDeLivros(naEstante: estante.id)
                resumos.append(EstanteResumo(estante: estante, quantidadeDeLivros: quantidade))
            }
            estado = resumos.isEmpty ? .vazio : .pronto(resumos)
        } catch {
            estado = .erro("Não foi possível carregar as estantes.")
        }
    }

    func criarEstante(nome: String) async {
        guard let nome = Self.nomeValido(nome) else { return }
        await gravar(Estante(nome: nome), falha: "Não foi possível criar a estante.")
    }

    func renomear(_ estante: Estante, para nome: String) async {
        guard let nome = Self.nomeValido(nome), nome != estante.nome else { return }
        var renomeada = estante
        renomeada.nome = nome
        await gravar(renomeada, falha: "Não foi possível renomear a estante.")
    }

    private func gravar(_ estante: Estante, falha: String) async {
        do {
            try await repositorio.salvar(estante)
        } catch {
            mensagemDeErro = falha
        }
        await carregar()
    }
}
