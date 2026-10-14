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
    /// Etiquetas já usadas na estante escolhida, de onde saem as sugestões do campo da prateleira.
    @Published private(set) var prateleirasDaEstante: [String] = []
    @Published private(set) var salvando = false
    @Published var mensagemDeErro: String?
    /// Os erros só aparecem depois da primeira tentativa de salvar: um formulário novo todo em vermelho assusta à toa.
    @Published private(set) var tentouSalvar = false
    /// A foto da miniatura como está no formulário (já reduzida pela tela); `nil` = sem foto.
    @Published private(set) var foto: Data?

    let modo: Modo
    /// O livro como está no banco (só na edição): o que o formulário não mostra sai dele.
    private var original: Livro?
    /// O rascunho ao abrir, para saber se o usuário mudou algo.
    private var rascunhoInicial: RascunhoLivro
    /// A foto ao abrir: só se grava a foto se ela mudou.
    private var fotoInicial: Data?
    private let repositorio: BibliotecaRepositorio
    /// Avisa que a foto de um livro mudou (a montagem liga ao `esquecer` do `CarregadorDeMiniaturas`, que é da
    /// interface; assim o ViewModel fica só com Foundation).
    private let fotoTrocada: @MainActor (UUID) -> Void

    init(modo: Modo, repositorio: BibliotecaRepositorio, fotoTrocada: @escaping @MainActor (UUID) -> Void) {
        self.modo = modo
        self.repositorio = repositorio
        self.fotoTrocada = fotoTrocada
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
    var alterado: Bool { rascunho != rascunhoInicial || foto != fotoInicial }

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
                // Sem a foto o formulário ainda funciona, mas avisa: senão "Adicionar foto" faria parecer que o
                // livro não tem foto. Salvar sem mexer nela não a apaga (`foto == fotoInicial`).
                do {
                    foto = try await repositorio.fotoMiniatura(doLivro: livroId)
                } catch {
                    mensagemDeErro = "Não foi possível abrir a foto atual."
                }
                fotoInicial = foto
            }
            await carregarPrateleiras()
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
        } catch {
            mensagemDeErro = "Não foi possível salvar o livro."
            return false
        }
        // Já gravado: se a foto falhar e o usuário tentar de novo, atualiza este livro em vez de criar outro.
        original = livro
        guard foto != fotoInicial else { return true }
        do {
            try await repositorio.salvarFotoMiniatura(foto, doLivro: livro.id)
        } catch {
            // A folha fica aberta com a foto escolhida: "Salvar" de novo tenta só gravar a foto outra vez.
            mensagemDeErro = "O livro foi salvo, mas a foto não."
            return false
        }
        fotoInicial = foto
        fotoTrocada(livro.id)
        return true
    }

    // MARK: Foto

    func escolherFoto(_ dados: Data) {
        foto = dados
    }

    func removerFoto() {
        foto = nil
    }

    // MARK: Prateleira

    var sugestoesDePrateleira: [String] {
        SugestaoDePrateleira.sugerir(para: rascunho.prateleira, entre: prateleirasDaEstante)
    }

    /// Relida a cada troca de estante: as etiquetas são de cada estante.
    func carregarPrateleiras() async {
        let estanteId = rascunho.estanteId
        // A sugestão é só uma ajuda: se a leitura falhar, o formulário segue sem ela.
        let etiquetas = (try? await repositorio.prateleiras(naEstante: estanteId)) ?? []
        // Trocando de estante duas vezes depressa, duas leituras correm juntas e a primeira pode voltar
        // por último: a resposta só vale se o formulário ainda estiver na estante pedida.
        guard rascunho.estanteId == estanteId else { return }
        prateleirasDaEstante = etiquetas
    }

    func escolherPrateleira(_ etiqueta: String) {
        rascunho.prateleira = etiqueta
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
        case (.isbnInvalido, _): return "ISBN inválido: confira os 10 ou 13 dígitos."
        }
    }
}
