import Foundation

/// Os livros de uma prateleira, na ordem em que a tela da estante os mostra.
struct GrupoDePrateleira: Equatable {
    /// A etiqueta como o usuário a escreveu; `nil` para os livros sem prateleira.
    let prateleira: String?
    let livros: [Livro]
}

/// Agrupa os livros de uma estante por prateleira, espelhando a estante física.
///
/// - Etiquetas que só diferem em maiúsculas, acentos ou espaços ("Caixa azul", "caixa azul ") são a mesma
///   prateleira (comparadas pela `Normalizacao.chave`); o grupo mostra a grafia mais usada.
/// - Grupos em ordem "natural" da etiqueta ("2ª de cima" antes de "10ª de cima"); "sem prateleira" no fim.
/// - Dentro do grupo: título sem acento; tomos da mesma obra pelo número do volume (sem volume primeiro);
///   depois o ano; o `id` só desempata para a ordem nunca depender da ordem de chegada.
enum AgrupamentoPorPrateleira {
    static func agrupar(_ livros: [Livro]) -> [GrupoDePrateleira] {
        var porChave: [String: [Livro]] = [:]
        for livro in livros {
            porChave[Normalizacao.chave(livro.prateleira ?? ""), default: []].append(livro)
        }

        let semPrateleira = porChave.removeValue(forKey: "")
        var grupos = porChave.values
            .map { GrupoDePrateleira(prateleira: grafiaMaisUsada(em: $0), livros: $0.sorted(by: vemAntes)) }
            .sorted { ($0.prateleira ?? "").localizedStandardCompare($1.prateleira ?? "") == .orderedAscending }
        if let semPrateleira = semPrateleira {
            grupos.append(GrupoDePrateleira(prateleira: nil, livros: semPrateleira.sorted(by: vemAntes)))
        }
        return grupos
    }

    /// A grafia mais frequente (aparada) entre os livros do grupo; no empate, a primeira em ordem alfabética.
    private static func grafiaMaisUsada(em livros: [Livro]) -> String {
        var contagem: [String: Int] = [:]
        for livro in livros {
            let grafia = (livro.prateleira ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            contagem[grafia, default: 0] += 1
        }
        return contagem.min { a, b in a.value != b.value ? a.value > b.value : a.key < b.key }?.key ?? ""
    }

    private static func vemAntes(_ a: Livro, _ b: Livro) -> Bool {
        let tituloA = Normalizacao.chave(a.titulo)
        let tituloB = Normalizacao.chave(b.titulo)
        if tituloA != tituloB {
            return tituloA.localizedStandardCompare(tituloB) == .orderedAscending
        }
        // `Int.min` põe quem não tem volume ou ano antes dos que têm.
        if a.volume != b.volume { return (a.volume ?? .min) < (b.volume ?? .min) }
        if a.ano != b.ano { return (a.ano ?? .min) < (b.ano ?? .min) }
        return a.id.uuidString < b.id.uuidString
    }
}
