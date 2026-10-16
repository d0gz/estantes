import Foundation

/// Um campo do livro como o detalhe o mostra ("Editora", "Malheiros"). Sem rótulo quando o título do grupo já diz
/// o que é (cada autor no cartão "Autores").
struct CampoDoLivro: Equatable {
    let rotulo: String?
    let valor: String
}

/// Um grupo de campos do detalhe ("Publicação") com os campos preenchidos.
struct GrupoDeCampos: Equatable, Identifiable {
    let titulo: String
    let campos: [CampoDoLivro]

    var id: String { titulo }
}

/// O topo do detalhe, abaixo da miniatura: o que identifica o livro na estante.
struct CabecalhoDoLivro: Equatable {
    let titulo: String
    let subtitulo: String?
    let volume: String?
    /// Um autor: o nome inteiro. Vários: só os sobrenomes, como na ABNT ("Cintra, Grinover e Dinamarco"; de 4 em
    /// diante, "Sarlet et al."). Os nomes inteiros ficam no cartão "Autores", onde a quebra de linha dentro de um
    /// nome não se confunde com outro autor.
    let autores: String?
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
    /// As categorias do livro (chips do cabeçalho), na ordem alfabética do repositório.
    @Published private(set) var categoriasDoLivro: [Categoria] = []

    let livroId: UUID
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
            // O livro guarda só os ids; nomes e cores vêm das categorias.
            categoriasDoLivro = try await repositorio.categorias().comIds(livro.categoriaIds)
            estado = .pronto(livro)
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

    /// Título, subtítulo, volume e a linha dos autores; vazios ou só de espaços somem.
    static func cabecalho(de livro: Livro) -> CabecalhoDoLivro {
        CabecalhoDoLivro(
            titulo: livro.titulo,
            subtitulo: preenchido(livro.subtitulo),
            volume: preenchido(textoDoVolume(livro)),
            autores: linhaDosAutores(autoresPreenchidos(livro))
        )
    }

    private static func linhaDosAutores(_ autores: [String]) -> String? {
        switch autores.count {
        case 0: return nil
        case 1: return autores[0]
        case 2, 3:
            let sobrenomes = autores.map(sobrenome)
            return sobrenomes.dropLast().joined(separator: ", ") + " e " + sobrenomes[sobrenomes.count - 1]
        default: return sobrenome(autores[0]) + " et al."
        }
    }

    /// O que vem antes da vírgula em "Sobrenome, Nome"; sem vírgula, o nome inteiro (não há como saber).
    private static func sobrenome(_ autor: String) -> String {
        guard let virgula = autor.firstIndex(of: ",") else { return autor }
        return preenchido(String(autor[..<virgula])) ?? autor
    }

    /// Os grupos de campos do detalhe, só com os campos preenchidos; grupo sem nenhum campo some.
    /// Título, subtítulo e volume não entram: estão no `cabecalho(de:)`. Os autores, sim, um por linha (o
    /// cabeçalho mostra só os sobrenomes), seguidos dos colaboradores, que nunca vão para o cabeçalho.
    static func grupos(de livro: Livro) -> [GrupoDeCampos] {
        let autores = autoresPreenchidos(livro)
        let grupos = [
            GrupoDeCampos(
                titulo: autores.count > 1 ? "Autores" : "Autor",
                campos: autores.map { CampoDoLivro(rotulo: nil, valor: $0) } + camposDosColaboradores(livro)
            ),
            GrupoDeCampos(titulo: "Obra", campos: campos([
                ("Parte", livro.parte),
                ("Número do volume", numeroDoVolumeForaDoCabecalho(livro)),
                ("Série", livro.serie),
                ("Artigos", textoDosArtigos(inicio: livro.artigosInicio, fim: livro.artigosFim)),
            ])),
            GrupoDeCampos(titulo: "Publicação", campos: campos([
                ("Editora", livro.editora),
                ("Local", livro.local),
                ("Edição", livro.edicao),
                ("Ano", livro.ano.map(String.init)),
                ("Páginas", livro.paginas.map(String.init)),
                ("ISBN", livro.isbn13),
            ])),
            GrupoDeCampos(titulo: "Na estante", campos: campos([
                ("Prateleira", livro.prateleira),
                ("Origem", textoDaOrigem(livro.origem)),
            ])),
        ]
        return grupos.filter { !$0.campos.isEmpty }
    }

    /// Descarta os valores ausentes ou só de espaços.
    private static func campos(_ pares: [(String, String?)]) -> [CampoDoLivro] {
        pares.compactMap { rotulo, valor in
            preenchido(valor).map { CampoDoLivro(rotulo: rotulo, valor: $0) }
        }
    }

    /// Depois dos autores, cada colaborador com o papel como rótulo ("Prefácio"); sem papel, "Colaborador".
    private static func camposDosColaboradores(_ livro: Livro) -> [CampoDoLivro] {
        livro.colaboradores.compactMap { colaborador in
            preenchido(colaborador.nome).map { nome in
                let papel = preenchido(colaborador.papel).map { $0.prefix(1).uppercased() + $0.dropFirst() }
                return CampoDoLivro(rotulo: papel ?? "Colaborador", valor: nome)
            }
        }
    }

    /// Os autores sem os vazios ou só de espaços, na ordem do livro.
    private static func autoresPreenchidos(_ livro: Livro) -> [String] {
        livro.autores.compactMap(preenchido)
    }

    /// O texto sem espaços nas pontas, ou `nil` se não sobrar nada.
    private static func preenchido(_ texto: String?) -> String? {
        guard let texto = texto?.trimmingCharacters(in: .whitespacesAndNewlines), !texto.isEmpty else { return nil }
        return texto
    }

    /// O rótulo impresso ("Tomo XLVIII") vence; sem ele, o número ("Vol. 48").
    static func textoDoVolume(_ livro: Livro) -> String? {
        preenchido(livro.volumeRotulo) ?? livro.volume.map { "Vol. \($0)" }
    }

    /// Com rótulo, o cabeçalho mostra só ele (`textoDoVolume`); o número vai para o cartão Obra, senão não
    /// apareceria em lugar nenhum. Sem rótulo, o número já está no cabeçalho ("Vol. 48").
    private static func numeroDoVolumeForaDoCabecalho(_ livro: Livro) -> String? {
        guard preenchido(livro.volumeRotulo) != nil else { return nil }
        return livro.volume.map(String.init)
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
