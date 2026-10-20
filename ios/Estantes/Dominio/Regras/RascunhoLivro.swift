import Foundation

/// O livro como o formulário o edita: cada campo é o texto que o usuário digitou.
///
/// Texto, e não `Int?`, porque "20a" no ano precisa existir enquanto o usuário digita para a tela
/// apontar o erro; um `Int?` só saberia dizer "vazio". A conversão para `Livro` acontece uma vez,
/// ao salvar, em `montar(sobre:)`, e é aqui que ficam as regras do cadastro manual.
///
/// Obrigatórios: título, ao menos um autor, editora e ano. A exigência é **só do formulário**:
/// no `Livro` esses campos continuam opcionais, porque fontes automáticas (LexML, Google Books)
/// e livros antigos podem não trazê-los.
struct RascunhoLivro: Equatable {
    enum Campo: Hashable, CaseIterable {
        case titulo, autores, editora, ano, paginas, isbn, volume, artigosInicio, artigosFim
    }

    enum Problema: Equatable {
        case obrigatorio
        /// Não é um número inteiro maior que zero.
        case numeroInvalido
        /// O artigo final vem antes do inicial ("Arts. 1779-1710").
        case fimAntesDoInicio
        /// Não é um ISBN-10 nem um ISBN-13 válido (letra, tamanho ou dígito verificador; ver `ISBN`).
        case isbnInvalido
    }

    var estanteId: UUID
    var titulo = ""
    var subtitulo = ""
    /// Um nome por campo da tela, na ordem (o primeiro é o autor principal).
    var autores: [String] = [""]
    /// Uma linha por colaborador, nome e papel como o usuário digitou. Começa vazia: não é obrigatório.
    var colaboradores: [Colaborador] = []
    var editora = ""
    var local = ""
    var edicao = ""
    var ano = ""
    var paginas = ""
    var isbn13 = ""
    var volume = ""
    var volumeRotulo = ""
    var parte = ""
    var serie = ""
    var artigosInicio = ""
    var artigosFim = ""
    var prateleira = ""

    /// Rascunho de um livro novo, já na estante de onde o usuário partiu.
    init(estanteId: UUID) {
        self.estanteId = estanteId
    }

    /// Rascunho para editar um livro existente.
    init(livro: Livro) {
        estanteId = livro.estanteId
        titulo = livro.titulo
        subtitulo = livro.subtitulo ?? ""
        autores = livro.autores.isEmpty ? [""] : livro.autores
        colaboradores = livro.colaboradores
        editora = livro.editora ?? ""
        local = livro.local ?? ""
        edicao = livro.edicao ?? ""
        ano = livro.ano.map(String.init) ?? ""
        paginas = livro.paginas.map(String.init) ?? ""
        isbn13 = livro.isbn13 ?? ""
        volume = livro.volume.map(String.init) ?? ""
        volumeRotulo = livro.volumeRotulo ?? ""
        parte = livro.parte ?? ""
        serie = livro.serie ?? ""
        artigosInicio = livro.artigosInicio.map(String.init) ?? ""
        artigosFim = livro.artigosFim.map(String.init) ?? ""
        prateleira = livro.prateleira ?? ""
    }

    /// Os problemas de cada campo; vazio quando o rascunho pode virar um `Livro`.
    func problemas() -> [Campo: Problema] {
        var problemas: [Campo: Problema] = [:]
        if Normalizacao.textoLimpo(titulo) == nil { problemas[.titulo] = .obrigatorio }
        if autoresLimpos.isEmpty { problemas[.autores] = .obrigatorio }
        if Normalizacao.textoLimpo(editora) == nil { problemas[.editora] = .obrigatorio }

        let numeros: [(Campo, String, Bool)] = [
            (.ano, ano, true), (.paginas, paginas, false), (.volume, volume, false),
            (.artigosInicio, artigosInicio, false), (.artigosFim, artigosFim, false),
        ]
        for (campo, texto, obrigatorio) in numeros {
            switch Self.numero(texto) {
            case .vazio where obrigatorio: problemas[campo] = .obrigatorio
            case .invalido: problemas[campo] = .numeroInvalido
            default: break
            }
        }

        if Normalizacao.textoLimpo(isbn13) != nil, ISBN.normalizar(isbn13) == nil {
            problemas[.isbn] = .isbnInvalido
        }

        if case .valor(let inicio) = Self.numero(artigosInicio), case .valor(let fim) = Self.numero(artigosFim), fim < inicio {
            problemas[.artigosFim] = .fimAntesDoInicio
        }
        return problemas
    }

    /// O `Livro` pronto para salvar, ou `nil` se houver problemas (`problemas()` diz quais).
    ///
    /// Na edição (`base` presente), mantém o que o formulário não mostra: id, data de entrada, origem,
    /// sumário, categorias, CDDir e URN. Sem `base`, nasce um livro novo com origem `.manual`.
    func montar(sobre base: Livro?) -> Livro? {
        guard problemas().isEmpty, let titulo = Normalizacao.textoLimpo(titulo) else { return nil }

        var livro = base ?? Livro(estanteId: estanteId, titulo: titulo, origem: .manual)
        livro.estanteId = estanteId
        livro.titulo = titulo
        livro.subtitulo = Normalizacao.textoLimpo(subtitulo)
        livro.autores = autoresLimpos
        livro.colaboradores = colaboradoresLimpos
        livro.editora = Normalizacao.textoLimpo(editora)
        livro.local = Normalizacao.textoLimpo(local)
        livro.edicao = Normalizacao.textoLimpo(edicao)
        livro.ano = Self.numero(ano).valor
        livro.paginas = Self.numero(paginas).valor
        // Já validado em `problemas()`: aqui só vira os 13 dígitos (o ISBN-10 é convertido).
        livro.isbn13 = Normalizacao.textoLimpo(isbn13).flatMap(ISBN.normalizar)
        livro.volume = Self.numero(volume).valor
        livro.volumeRotulo = Normalizacao.textoLimpo(volumeRotulo)
        livro.parte = Normalizacao.textoLimpo(parte)
        livro.serie = Normalizacao.textoLimpo(serie)
        livro.artigosInicio = Self.numero(artigosInicio).valor
        livro.artigosFim = Self.numero(artigosFim).valor
        livro.prateleira = Normalizacao.textoLimpo(prateleira)
        return livro
    }

    // MARK: Conversões

    private var autoresLimpos: [String] {
        autores.compactMap(Normalizacao.textoLimpo)
    }

    /// Linha sem nome sai (o papel sozinho não diz quem); sem papel fica, com papel vazio.
    private var colaboradoresLimpos: [Colaborador] {
        colaboradores.compactMap { linha in
            Normalizacao.textoLimpo(linha.nome).map {
                Colaborador(nome: $0, papel: Normalizacao.textoLimpo(linha.papel) ?? "")
            }
        }
    }

    private enum Numero: Equatable {
        case vazio
        case invalido
        case valor(Int)

        var valor: Int? {
            if case .valor(let numero) = self { return numero }
            return nil
        }
    }

    /// Inteiro maior que zero. Aceita o ponto de milhar entre dígitos ("1.710"), como os artigos vêm impressos.
    private static func numero(_ texto: String) -> Numero {
        guard let limpo = Normalizacao.textoLimpo(texto) else { return .vazio }
        let partes = limpo.split(separator: ".", omittingEmptySubsequences: false)
        guard partes.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }),
              let numero = Int(partes.joined()), numero > 0
        else { return .invalido }
        return .valor(numero)
    }
}

private extension Character {
    /// `isNumber` aceitaria "½" e algarismos de outras escritas, que `Int(_:)` não converte.
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
