import Foundation

/// Estado da tela "Busca": o texto, os filtros (os chips e as telas Filtros e Categorias) e o que a lista mostra.
@MainActor
final class BuscaViewModel: ObservableObject {
    enum Estado: Equatable {
        /// Nada digitado e nenhum filtro: a tela explica o que dá para buscar.
        case dica
        /// Nunca com a lista vazia: aí o estado é `.nadaEncontrado`.
        case resultados(RespostaBusca)
        /// Com o texto buscado (aparado), e não o que está sendo digitado: a mensagem não muda antes da próxima
        /// resposta. `nil` quando a busca foi só por filtro.
        case nadaEncontrado(texto: String?)
        case erro(String)
    }

    /// Mudar o texto desliga o "Buscar exatamente": a opção valia para a palavra que estava escrita.
    @Published var texto = "" {
        didSet { if texto != oldValue { exatamente = false } }
    }
    @Published var filtro = FiltroBusca()
    @Published private(set) var estado: Estado = .dica
    /// Ligado pelo "Buscar exatamente": a busca não troca palavras desconhecidas.
    @Published private(set) var exatamente = false
    /// Os chips de filtro: lidos por `carregarOpcoes`, na ordem do repositório.
    @Published private(set) var estantes: [Estante] = []
    @Published private(set) var categorias: [Categoria] = []

    /// Tudo o que muda o resultado. A tela busca com `.task(id: chave)`: mudou a chave, a busca
    /// anterior é cancelada e outra começa.
    struct Chave: Equatable {
        let texto: String
        let filtro: FiltroBusca
        let exatamente: Bool
        /// Sobe em `pedirNovaBusca`: a mesma consulta roda de novo (o banco pode ter mudado).
        let versao: Int
    }

    var chave: Chave { Chave(texto: texto, filtro: filtro, exatamente: exatamente, versao: versao) }

    @Published private var versao = 0

    private let biblioteca: BibliotecaIndexada

    init(biblioteca: BibliotecaIndexada) {
        self.biblioteca = biblioteca
    }

    // MARK: Filtros

    /// Lê as estantes e as categorias dos chips. Tira do filtro as que não existem mais: sem chip na
    /// tela, o usuário não teria como desmarcá-las. Se a leitura falhar, os chips ficam como estavam
    /// (a busca continua funcionando sem eles).
    func carregarOpcoes() async {
        guard let estantes = try? await biblioteca.estantes(),
              let categorias = try? await biblioteca.categorias() else { return }
        self.estantes = estantes
        self.categorias = categorias
        filtro.estanteIds.formIntersection(estantes.map(\.id))
        filtro.categoriaIds.formIntersection(categorias.map(\.id))
    }

    /// O nome que a linha do resultado mostra; `nil` se a estante não está entre as lidas.
    func nomeDaEstante(_ id: UUID) -> String? {
        estantes.first { $0.id == id }?.nome
    }

    /// O "n" do chip "Filtros (n)": quantos dos filtros de texto da tela Filtros estão ligados (autor, editora, anos;
    /// os dois anos contam como um). Lido do `preparado()`, para valer a mesma regra do motor
    /// ("em branco = sem filtro").
    var quantidadeDeFiltrosDeTexto: Int {
        let preparado = filtro.preparado()
        return [
            !preparado.termosDoAutor.isEmpty,
            preparado.editora != nil,
            preparado.anoMinimo != nil || preparado.anoMaximo != nil,
        ].filter { $0 }.count
    }

    /// O ano de um campo da tela Filtros: só com 4 dígitos. Enquanto se digita "1972", o campo passa por "1",
    /// "19" e "197", e filtrar por eles esvaziaria e encheria a lista a cada tecla.
    static func ano(deTexto texto: String) -> Int? {
        guard texto.count == 4, texto.allSatisfy(\.isASCII), texto.allSatisfy(\.isNumber) else { return nil }
        return Int(texto)
    }

    /// "De" depois de "Até": nenhum livro passa, e a tela Filtros explica por quê em vez de mostrar só a lista vazia.
    var faixaDeAnosInvertida: Bool {
        guard let minimo = filtro.anoMinimo, let maximo = filtro.anoMaximo else { return false }
        return minimo > maximo
    }

    /// Marca ou desmarca o chip da estante (dentro das estantes vale "qualquer destas").
    func alternar(estante id: UUID) {
        if filtro.estanteIds.remove(id) == nil { filtro.estanteIds.insert(id) }
    }

    /// Marca ou desmarca uma categoria na tela Categorias da busca (várias ao mesmo tempo; vale "qualquer destas").
    func alternar(categoria id: UUID) {
        if filtro.categoriaIds.remove(id) == nil { filtro.categoriaIds.insert(id) }
    }

    /// O rótulo do chip: "Categorias" sem nenhuma, o nome com uma, "Categorias (2)" com mais (o chip não cresce
    /// sem limite). Conta só as categorias lidas.
    var rotuloDasCategorias: String {
        let marcadas = categorias.filter { filtro.categoriaIds.contains($0.id) }
        switch marcadas.count {
        case 0: return "Categorias"
        case 1: return marcadas[0].nome
        default: return "Categorias (\(marcadas.count))"
        }
    }

    /// Os chips da linha do resultado, na ordem da lista (alfabética). Id sem categoria lida fica de fora.
    func categorias(de livro: Livro) -> [Categoria] {
        categorias.filter { livro.categoriaIds.contains($0.id) }
    }

    // MARK: Busca

    /// Só liga a opção: quem busca de novo é a tela, porque a `chave` mudou.
    func buscarExatamente() {
        exatamente = true
    }

    /// Roda a mesma consulta de novo (na volta do Detalhe, o livro pode ter mudado). Muda a `chave`, e não chama
    /// `buscar` direto: assim o `.task(id:)` cancela a busca anterior, em vez de duas correrem juntas.
    func pedirNovaBusca() {
        versao += 1
    }

    func buscar() async {
        // A mesma regra do motor: só espaços ou só palavras vazias ("de") contam como nada digitado.
        let semTexto = Tokenizador.palavras(texto).isEmpty
        if semTexto, filtro.estaVazio {
            estado = .dica
            return
        }
        do {
            let resposta = try await biblioteca.buscar(texto, filtro: filtro, corrigir: !exatamente)
            // A tela cancela a busca da tecla anterior (`.task(id:)`), mas o actor termina o que começou:
            // a resposta velha não pode cobrir a nova.
            guard !Task.isCancelled else { return }
            let buscado = semTexto ? nil : texto.trimmingCharacters(in: .whitespacesAndNewlines)
            estado = resposta.resultados.isEmpty ? .nadaEncontrado(texto: buscado) : .resultados(resposta)
        } catch {
            guard !Task.isCancelled else { return }
            // Só a montagem do índice lê o banco; a próxima busca tenta montar de novo.
            estado = .erro("Não foi possível preparar a busca.")
        }
    }
}
