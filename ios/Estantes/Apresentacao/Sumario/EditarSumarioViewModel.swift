import Foundation

/// Folha "Editar sumário", aberta pelo cartão do Detalhe. As mudanças ficam num `RascunhoSumario` e só são
/// gravadas no "Salvar"; "Cancelar" descarta (decisão de 20/10, mesmo fluxo da escolha de categorias).
///
/// Nada é corrigido sozinho: com erro (título vazio, salto de nível), o "Salvar" não grava e cada item marca o seu
/// erro. O aviso de página não espera o "Salvar" nem impede de gravar.
@MainActor
final class EditarSumarioViewModel: ObservableObject {
    enum Estado: Equatable {
        case carregando
        /// O livro foi apagado ou o id não existe.
        case naoEncontrado
        case pronto
        case erro(String)
    }

    @Published private(set) var estado: Estado = .carregando
    @Published private(set) var rascunho = RascunhoSumario(itens: [])
    /// Liga na primeira tentativa de salvar com erro (como no formulário do livro).
    @Published private(set) var mostrarErros = false
    @Published private(set) var salvando = false
    @Published var mensagemDeErro: String?

    private let livroId: UUID
    /// O livro relido ao abrir: ao gravar, só o sumário muda nele.
    private var livro: Livro?
    /// O rascunho como foi carregado, para saber se há o que perder ao fechar a folha.
    private var original = RascunhoSumario(itens: [])
    private let repositorio: BibliotecaRepositorio

    init(livroId: UUID, repositorio: BibliotecaRepositorio) {
        self.livroId = livroId
        self.repositorio = repositorio
    }

    func carregar() async {
        do {
            guard let livro = try await repositorio.livro(id: livroId) else {
                estado = .naoEncontrado
                return
            }
            self.livro = livro
            rascunho = RascunhoSumario(itens: livro.itensSumario)
            original = rascunho
            estado = .pronto
        } catch {
            estado = .erro("Não foi possível carregar o sumário.")
        }
    }

    var itens: [RascunhoSumario.Item] { rascunho.itens }

    /// Mudou algo desde que a folha abriu: arrastar para fechar fica bloqueado.
    var alterado: Bool { rascunho != original }

    func item(id: UUID) -> RascunhoSumario.Item? {
        rascunho.itens.first { $0.id == id }
    }

    // MARK: Edição (repassada ao rascunho)

    func atualizar(_ item: RascunhoSumario.Item) { rascunho.atualizar(item) }
    @discardableResult
    func adicionarNoFim() -> UUID { rascunho.adicionarNoFim() }
    /// "Inserir abaixo", do menu de contexto.
    @discardableResult
    func inserir(abaixoDe id: UUID) -> UUID? { rascunho.inserir(abaixoDe: id) }
    func mover(de origem: IndexSet, para destino: Int) { rascunho.mover(de: origem, para: destino) }
    func aumentarNivel(id: UUID) { rascunho.aumentarNivel(id: id) }
    func diminuirNivel(id: UUID) { rascunho.diminuirNivel(id: id) }
    func nivelMaximo(id: UUID) -> Int { rascunho.nivelMaximo(id: id) }

    func apagar(id: UUID) {
        guard let indice = indice(de: id) else { return }
        rascunho.apagar(IndexSet(integer: indice))
    }

    /// "Próximo item" na tela de item: um item vazio logo abaixo do que acabou de ser digitado, no mesmo nível.
    func proximoItem(depoisDe id: UUID) -> UUID? {
        rascunho.inserir(abaixoDe: id)
    }

    /// Ao voltar da tela de item: um item sem nada escrito (aberto pelo "Adicionar item" ou pelo "Próximo item" e
    /// abandonado) sai, para não travar o "Salvar" com um título vazio que ninguém escreveu.
    func descartarSeVazio(id: UUID) {
        guard let item = item(id: id),
              [item.numeracao, item.titulo, item.pagina].allSatisfy({ Normalizacao.textoLimpo($0) == nil })
        else { return }
        apagar(id: id)
    }

    // MARK: Problemas por item

    /// O erro do item, só depois de tentar salvar.
    func erro(doItem id: UUID) -> String? {
        guard mostrarErros, let indice = indice(de: id) else { return nil }
        return rascunho.validacao().erros.first { $0.indice == indice }.map { Self.texto(de: $0) }
    }

    /// O aviso do item, sempre (não impede de gravar).
    func aviso(doItem id: UUID) -> String? {
        guard let indice = indice(de: id) else { return nil }
        return rascunho.validacao().avisos.first { $0.indice == indice }.map { Self.texto(de: $0) }
    }

    /// Quantos itens têm erro, para o topo da lista dizer o que impede de salvar.
    var quantidadeDeItensComErro: Int {
        guard mostrarErros else { return 0 }
        return Set(rascunho.validacao().erros.map(\.indice)).count
    }

    private static func texto(de problema: ValidacaoSumario.Problema) -> String {
        switch problema {
        case .nivelInvalido:
            return "O nível precisa ser 1 ou mais."
        case .saltoDeNivel(let indice):
            return indice == 0
                ? "O primeiro item precisa ser de nível 1."
                : "O nível pula mais de um em relação ao item de cima."
        case .tituloVazio:
            return "Falta o título."
        case .paginaMenorQueAnterior:
            return "A página é menor que a do item anterior."
        }
    }

    private func indice(de id: UUID) -> Int? {
        rascunho.itens.firstIndex { $0.id == id }
    }

    // MARK: Gravar

    /// Devolve `true` se gravou: a folha então fecha.
    func salvar() async -> Bool {
        guard var livro = livro else { return false }
        guard let itens = rascunho.montar() else {
            mostrarErros = true
            return false
        }
        livro.itensSumario = itens
        salvando = true
        defer { salvando = false }
        do {
            try await repositorio.salvar(livro)
            self.livro = livro
            original = rascunho
            return true
        } catch {
            mensagemDeErro = "Não foi possível salvar o sumário."
            return false
        }
    }
}

private extension ValidacaoSumario.Problema {
    var indice: Int {
        switch self {
        case .nivelInvalido(let indice), .saltoDeNivel(let indice), .tituloVazio(let indice),
             .paginaMenorQueAnterior(let indice):
            return indice
        }
    }
}
