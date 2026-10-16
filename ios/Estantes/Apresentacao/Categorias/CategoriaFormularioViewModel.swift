import Foundation

/// Folha de criar ou editar uma categoria: nome e cor. As regras ficam no Domínio (`NomeDeCategoria` para o
/// nome, `CorSugerida` para a cor inicial); aqui ficam só o estado da folha e a gravação.
@MainActor
final class CategoriaFormularioViewModel: ObservableObject {
    /// `Identifiable` para abrir a folha direto com `sheet(item:)`.
    enum Modo: Equatable, Identifiable {
        case nova
        case edicao(Categoria)

        var id: String {
            switch self {
            case .nova: return "nova"
            case .edicao(let categoria): return categoria.id.uuidString
            }
        }
    }

    enum Estado: Equatable {
        case carregando
        case pronto
        case erro(String)
    }

    @Published var nome: String
    @Published var cor: CorCategoria
    @Published private(set) var estado: Estado = .carregando
    @Published private(set) var salvando = false
    @Published var mensagemDeErro: String?
    /// O erro do nome só aparece depois da primeira tentativa de salvar, como no formulário do livro.
    @Published private(set) var tentouSalvar = false

    let modo: Modo
    /// Fixo desde a abertura: tentar salvar de novo depois de uma falha não cria outra categoria.
    private let id: UUID
    /// As categorias já cadastradas: de onde saem a cor sugerida e a checagem de nome repetido.
    private var existentes: [Categoria] = []
    private let repositorio: BibliotecaRepositorio

    init(modo: Modo, repositorio: BibliotecaRepositorio) {
        self.modo = modo
        self.repositorio = repositorio
        switch modo {
        case .nova:
            id = UUID()
            nome = ""
            // Trocada pela sugerida ao carregar; até lá a folha mostra "carregando".
            cor = .vermelho
        case .edicao(let categoria):
            id = categoria.id
            nome = categoria.nome
            cor = categoria.cor
        }
    }

    func carregar() async {
        do {
            existentes = try await repositorio.categorias()
            if modo == .nova {
                cor = CorSugerida.sugerir(existentes: existentes)
            }
            estado = .pronto
        } catch {
            estado = .erro("Não foi possível abrir a categoria.")
        }
    }

    var titulo: String {
        modo == .nova ? "Nova categoria" : "Editar categoria"
    }

    /// O texto embaixo do campo, ou `nil` se o nome serve (ou se ainda não se tentou salvar).
    var problemaDoNome: String? {
        guard tentouSalvar else { return nil }
        switch NomeDeCategoria.validar(nomeAparado, existentes: existentes, ignorando: id) {
        case .none: return nil
        case .vazio: return "Dê um nome à categoria."
        case .repetido(let existente): return "Já existe a categoria \"\(existente.nome)\"."
        }
    }

    /// Devolve a categoria gravada (a folha de escolha marca a nova no livro), ou `nil` se não gravou.
    func salvar() async -> Categoria? {
        tentouSalvar = true
        guard problemaDoNome == nil else { return nil }
        let categoria = Categoria(id: id, nome: nomeAparado, cor: cor)
        salvando = true
        defer { salvando = false }
        do {
            try await repositorio.salvar(categoria)
            return categoria
        } catch {
            mensagemDeErro = "Não foi possível salvar a categoria."
            return nil
        }
    }

    private var nomeAparado: String {
        nome.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
