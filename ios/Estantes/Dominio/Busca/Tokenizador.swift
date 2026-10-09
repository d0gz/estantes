import Foundation

/// Transforma um texto nos termos que o índice da busca guarda e que a consulta procura.
///
/// Índice e consulta passam pelo mesmo tokenizador: se cada um normalizasse de um jeito,
/// "Ação" indexado nunca casaria com "acao" digitado.
/// As palavras vazias ficam aqui, e não em `Normalizacao`, porque a normalização também compara
/// nomes de categoria, e ali "Direito do Trabalho" e "Direito Trabalho" precisam continuar diferentes.
enum Tokenizador {
    /// Artigos, preposições e contrações sem valor para a busca, já sem acento ("à" vira "a").
    /// Palavras jurídicas curtas ("lei", "art", "cpc") ficam de fora de propósito.
    static let palavrasVazias: Set<String> = [
        "a", "o", "as", "os", "ao", "aos", "um", "uma", "uns", "umas",
        "de", "da", "do", "das", "dos", "e", "em", "no", "na", "nos", "nas",
        "num", "numa", "para", "por", "pelo", "pela", "pelos", "pelas", "com", "ou", "que", "se",
    ]

    /// Os termos do texto, na ordem e com repetições (o BM25F conta a frequência de cada um).
    /// "Lei 8.078/90 – Código de Defesa do Consumidor" → ["lei", "8078", "90", "codigo", "defesa", "consumidor"]
    static func termos(_ texto: String) -> [String] {
        let caracteres = Array(Normalizacao.chave(texto))
        var termos: [String] = []
        var atual = ""

        for (i, caractere) in caracteres.enumerated() {
            if fazParteDeTermo(caractere) {
                atual.append(caractere)
            } else if caractere == ".", pontoEntreDigitos(caracteres, i) {
                // Separador de milhar em número de lei: "8.078" fica "8078", como quem digita sem ponto.
                continue
            } else if !atual.isEmpty {
                termos.append(atual)
                atual = ""
            }
        }
        if !atual.isEmpty { termos.append(atual) }

        return termos.filter { !palavrasVazias.contains($0) }
    }

    /// Letras e dígitos formam termos; todo o resto separa. Os indicadores ordinais (º, ª) o Unicode
    /// classifica como letra, mas aqui separam, para que "5º" e "5" sejam o mesmo termo.
    private static func fazParteDeTermo(_ caractere: Character) -> Bool {
        guard caractere != "º", caractere != "ª" else { return false }
        return caractere.isLetter || caractere.isNumber
    }

    private static func pontoEntreDigitos(_ caracteres: [Character], _ i: Int) -> Bool {
        i > 0 && i + 1 < caracteres.count && caracteres[i - 1].isNumber && caracteres[i + 1].isNumber
    }
}
