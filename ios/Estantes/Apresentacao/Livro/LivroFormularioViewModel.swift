import Foundation

/// Formulário de adicionar ou editar um livro à mão. As regras do cadastro ficam no `RascunhoLivro`
/// (Domínio); aqui ficam só o estado da tela e a gravação.
@MainActor
final class LivroFormularioViewModel: ObservableObject {
    enum Modo: Equatable {
        case novo(estanteId: UUID)
        /// Recebe o id e relê o livro, como o detalhe: a struct que a tela tinha pode estar velha.
        case edicao(livroId: UUID)
    }

    enum Estado: Equatable {
        case carregando
        case pronto
        case erro(String)
    }

    @Published var rascunho: RascunhoLivro
    @Published private(set) var estado: Estado = .carregando
    /// Opções do seletor de estante.
    @Published private(set) var estantes: [Estante] = []
    @Published private(set) var salvando = false
    @Published var mensagemDeErro: String?
    /// Os erros só aparecem depois da primeira tentativa de salvar: um formulário novo todo em vermelho assusta à toa.
    @Published private(set) var tentouSalvar = false

    let modo: Modo
    /// O livro como está no banco (só na edição): o que o formulário não mostra sai dele.
    private var original: Livro?
    /// O rascunho ao abrir, para saber se o usuário mudou algo.
    private var rascunhoInicial: RascunhoLivro
    private let repositorio: BibliotecaRepositorio

    init(modo: Modo, repositorio: BibliotecaRepositorio) {
        self.modo = modo
        self.repositorio = repositorio
        // Na edição, um rascunho provisório até o `carregar()` trazer o livro.
        let estanteId: UUID
        switch modo {
        case .novo(let id): estanteId = id
        case .edicao: estanteId = UUID()
        }
        let inicial = RascunhoLivro(estanteId: estanteId)
        rascunho = inicial
        rascunhoInicial = inicial
    }

    var titulo: String {
        switch modo {
        case .novo: return "Novo livro"
        case .edicao: return "Editar livro"
        }
    }

    /// Com alterações, puxar a folha para baixo não fecha (não se perde o que foi digitado por engano).
    var alterado: Bool { rascunho != rascunhoInicial }

    /// Problemas a mostrar embaixo de cada campo.
    var problemas: [RascunhoLivro.Campo: RascunhoLivro.Problema] {
        tentouSalvar ? rascunho.problemas() : [:]
    }

    func carregar() async {
        do {
            estantes = try await repositorio.estantes()
            if case .edicao(let livroId) = modo {
                guard let livro = try await repositorio.livro(id: livroId) else {
                    estado = .erro("O livro não existe mais.")
                    return
                }
                original = livro
                rascunho = RascunhoLivro(livro: livro)
                rascunhoInicial = rascunho
            }
            estado = .pronto
        } catch {
            estado = .erro("Não foi possível abrir o formulário.")
        }
    }

    /// Devolve `true` se gravou: a tela então fecha a folha.
    func salvar() async -> Bool {
        tentouSalvar = true
        guard let livro = rascunho.montar(sobre: original) else { return false }
        salvando = true
        defer { salvando = false }
        do {
            try await repositorio.salvar(livro)
            return true
        } catch {
            mensagemDeErro = "Não foi possível salvar o livro."
            return false
        }
    }

    // MARK: Autores

    func adicionarAutor() {
        rascunho.autores.append("")
    }

    // `remove(atOffsets:)` e `move(fromOffsets:toOffset:)` existem, mas vêm do SwiftUI;
    // os ViewModels ficam só com Foundation, então as duas operações são feitas à mão.

    func apagarAutores(em posicoes: IndexSet) {
        for posicao in posicoes.sorted(by: >) {
            rascunho.autores.remove(at: posicao)
        }
    }

    /// `destino` segue a convenção do `onMove` da `List`: a posição na lista *antes* de tirar os movidos.
    func moverAutores(de origem: IndexSet, para destino: Int) {
        let movidos = origem.map { rascunho.autores[$0] }
        var restantes = rascunho.autores.enumerated().filter { !origem.contains($0.offset) }.map(\.element)
        let antesDoDestino = origem.filter { $0 < destino }.count
        restantes.insert(contentsOf: movidos, at: destino - antesDoDestino)
        rascunho.autores = restantes
    }

    // MARK: Textos

    static func mensagem(_ problema: RascunhoLivro.Problema, em campo: RascunhoLivro.Campo) -> String {
        switch (problema, campo) {
        case (.obrigatorio, .autores): return "Informe ao menos um autor."
        case (.obrigatorio, _): return "Obrigatório."
        case (.numeroInvalido, .ano): return "Use só números (ex.: 2014)."
        case (.numeroInvalido, _): return "Use um número inteiro maior que zero."
        case (.fimAntesDoInicio, _): return "O artigo final vem antes do inicial."
        }
    }
}
