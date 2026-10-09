import Foundation

/// Uma estante como a tela inicial a mostra: a estante e quantos livros ela tem.
/// Mora na Apresentação porque a contagem é um dado da tela, não uma propriedade da `Estante`.
struct EstanteResumo: Identifiable, Equatable {
    let estante: Estante
    let quantidadeDeLivros: Int

    var id: UUID { estante.id }
}

/// Tudo o que a confirmação de "apagar estante" precisa mostrar, lido do banco na hora do pedido.
struct PedidoDeExclusao: Identifiable, Equatable {
    let estante: Estante
    let quantidadeDeLivros: Int
    /// As outras estantes, que podem receber os livros. Nunca inclui a própria.
    let destinosPossiveis: [Estante]

    var id: UUID { estante.id }
    /// Só faz sentido mover se há livros e algum lugar para onde levá-los.
    var podeMover: Bool { quantidadeDeLivros > 0 && !destinosPossiveis.isEmpty }
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

    // MARK: Apagar estante

    /// Prepara a confirmação. A quantidade é relida do banco (e não tirada do cartão): numa ação
    /// destrutiva, o número mostrado precisa ser o de agora.
    /// Devolve o pedido em vez de guardá-lo num `@Published`: qual folha está aberta é estado da tela.
    func pedidoDeExclusao(de estante: Estante) async -> PedidoDeExclusao? {
        do {
            let quantidade = try await repositorio.quantidadeDeLivros(naEstante: estante.id)
            let outras = try await repositorio.estantes().filter { $0.id != estante.id }
            return PedidoDeExclusao(estante: estante, quantidadeDeLivros: quantidade, destinosPossiveis: outras)
        } catch {
            mensagemDeErro = "Não foi possível preparar a exclusão da estante."
            return nil
        }
    }

    /// Apaga a estante. Com `destino`, os livros vão para lá antes; sem ele, vão junto (cascata).
    func apagar(_ pedido: PedidoDeExclusao, movendoLivrosPara destino: Estante?) async {
        do {
            try await repositorio.apagarEstante(id: pedido.estante.id, moverLivrosPara: destino?.id)
        } catch {
            mensagemDeErro = "Não foi possível apagar a estante."
        }
        await carregar()
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
