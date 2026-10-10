import Foundation

/// Um campo do livro como o detalhe o mostra ("Editora", "Malheiros").
struct CampoDoLivro: Equatable, Identifiable {
    let rotulo: String
    let valor: String

    var id: String { rotulo }
}

/// Uma seção do detalhe ("Publicação") com os campos preenchidos.
struct SecaoDoLivro: Equatable, Identifiable {
    let titulo: String
    let campos: [CampoDoLivro]

    var id: String { titulo }
}

/// Detalhe de um livro. Recebe só o id e relê o livro do banco: uma struct guardada no link
/// da navegação estaria velha depois de uma edição.
@MainActor
final class LivroDetalheViewModel: ObservableObject {
    enum Estado: Equatable {
        case carregando
        /// O livro foi apagado (por esta tela ou outra) ou o id não existe.
        case naoEncontrado
        case pronto(Livro)
        case erro(String)
    }

    @Published private(set) var estado: Estado = .carregando
    @Published var mensagemDeErro: String?

    let livroId: UUID
    private let repositorio: BibliotecaRepositorio

    init(livroId: UUID, repositorio: BibliotecaRepositorio) {
        self.livroId = livroId
        self.repositorio = repositorio
    }

    func carregar() async {
        do {
            estado = try await repositorio.livro(id: livroId).map(Estado.pronto) ?? .naoEncontrado
        } catch {
            estado = .erro("Não foi possível carregar o livro.")
        }
    }

    /// Devolve `true` se apagou: a tela então volta para a estante.
    func apagar() async -> Bool {
        do {
            try await repositorio.apagarLivro(id: livroId)
            return true
        } catch {
            mensagemDeErro = "Não foi possível apagar o livro."
            return false
        }
    }

    // MARK: Campos mostrados

    /// As seções do detalhe, só com os campos preenchidos; seção sem nenhum campo some.
    /// O título não entra: é o cabeçalho da tela.
    static func secoes(de livro: Livro) -> [SecaoDoLivro] {
        let secoes = [
            SecaoDoLivro(titulo: "Obra", campos: campos([
                ("Subtítulo", livro.subtitulo),
                ("Parte", livro.parte),
                ("Volume", textoDoVolume(livro)),
                ("Série", livro.serie),
                ("Artigos", textoDosArtigos(inicio: livro.artigosInicio, fim: livro.artigosFim)),
            ])),
            SecaoDoLivro(titulo: "Autoria", campos: campos([
                (livro.autores.count > 1 ? "Autores" : "Autor", livro.autores.isEmpty ? nil : livro.autores.joined(separator: "\n")),
            ])),
            SecaoDoLivro(titulo: "Publicação", campos: campos([
                ("Editora", livro.editora),
                ("Local", livro.local),
                ("Edição", livro.edicao),
                ("Ano", livro.ano.map(String.init)),
                ("Páginas", livro.paginas.map(String.init)),
                ("ISBN", livro.isbn13),
            ])),
            SecaoDoLivro(titulo: "Na estante", campos: campos([
                ("Prateleira", livro.prateleira),
                ("Origem", textoDaOrigem(livro.origem)),
            ])),
        ]
        return secoes.filter { !$0.campos.isEmpty }
    }

    /// Descarta os valores ausentes ou só de espaços.
    private static func campos(_ pares: [(String, String?)]) -> [CampoDoLivro] {
        pares.compactMap { rotulo, valor in
            guard let valor = valor?.trimmingCharacters(in: .whitespacesAndNewlines), !valor.isEmpty else { return nil }
            return CampoDoLivro(rotulo: rotulo, valor: valor)
        }
    }

    /// O rótulo impresso ("Tomo XLVIII") vence; sem ele, o número ("Vol. 48").
    static func textoDoVolume(_ livro: Livro) -> String? {
        livro.volumeRotulo ?? livro.volume.map { "Vol. \($0)" }
    }

    static func textoDosArtigos(inicio: Int?, fim: Int?) -> String? {
        switch (inicio, fim) {
        case let (inicio?, fim?): return inicio == fim ? "Art. \(inicio)" : "Arts. \(inicio)–\(fim)"
        case let (inicio?, nil): return "A partir do art. \(inicio)"
        case let (nil, fim?): return "Até o art. \(fim)"
        case (nil, nil): return nil
        }
    }

    static func textoDaOrigem(_ origem: OrigemLivro) -> String {
        switch origem {
        case .lexml: return "LexML"
        case .googlebooks: return "Google Books"
        case .gemini: return "Gemini"
        case .manual: return "Cadastro manual"
        }
    }
}
