import Foundation

/// Estado da busca do Inicio: o texto, os filtros (as chips) e o que a lista mostra.
@MainActor
final class BuscaViewModel: ObservableObject {
    enum Estado: Equatable {
        /// Nada digitado e nenhum filtro: a tela explica o que dá para buscar.
        case dica
        /// Nunca com a lista vazia: aí o estado é `.nadaEncontrado`.
        case resultados(RespostaBusca)
        case nadaEncontrado
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
    }

    var chave: Chave { Chave(texto: texto, filtro: filtro, exatamente: exatamente) }

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

    /// O "n" do chip "Filtros (n)": quantos dos filtros da folha estão ligados (autor, editora, anos;
    /// os dois anos contam como um). Lido do `preparado()`, para valer a mesma regra do motor
    /// ("em branco = sem filtro").
    var quantidadeNaFolha: Int {
        let preparado = filtro.preparado()
        return [
            !preparado.termosDoAutor.isEmpty,
            preparado.editora != nil,
            preparado.anoMinimo != nil || preparado.anoMaximo != nil,
        ].filter { $0 }.count
    }

    /// Marca ou desmarca o chip da estante (dentro das estantes vale "qualquer destas").
    func alternar(estante id: UUID) {
        if filtro.estanteIds.remove(id) == nil { filtro.estanteIds.insert(id) }
    }

    /// O menu "Categoria ▾" escolhe uma só (o `FiltroBusca` aceitaria várias); `nil` é "Todas as categorias".
    func escolher(categoria id: UUID?) {
        filtro.categoriaIds = id.map { [$0] } ?? []
    }

    /// A categoria do menu, para o rótulo do chip; `nil` sem nenhuma (ou se ela não está entre as lidas).
    var categoriaEscolhida: Categoria? {
        categorias.first { filtro.categoriaIds.contains($0.id) }
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

    func buscar() async {
        // A mesma regra do motor: só espaços ou só palavras vazias ("de") contam como nada digitado.
        if Tokenizador.palavras(texto).isEmpty, filtro.estaVazio {
            estado = .dica
            return
        }
        do {
            let resposta = try await biblioteca.buscar(texto, filtro: filtro, corrigir: !exatamente)
            // A tela cancela a busca da tecla anterior (`.task(id:)`), mas o actor termina o que começou:
            // a resposta velha não pode cobrir a nova.
            guard !Task.isCancelled else { return }
            estado = resposta.resultados.isEmpty ? .nadaEncontrado : .resultados(resposta)
        } catch {
            guard !Task.isCancelled else { return }
            // Só a montagem do índice lê o banco; a próxima busca tenta montar de novo.
            estado = .erro("Não foi possível preparar a busca.")
        }
    }
}
