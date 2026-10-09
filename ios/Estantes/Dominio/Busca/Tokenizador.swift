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

    /// Os termos do texto, na ordem e com repetições (o BM25F conta a frequência de cada um),
    /// já no singular (`Singular`): "Prisões" e "prisão" são o mesmo termo.
    /// "Lei 8.078/90 – Código de Defesa do Consumidor" → ["lei", "8078", "90", "codigo", "defesa", "consumidor"]
    /// "Sub-rogação nos arts. 1.710-1.779" → ["subrogacao", "art", "1710", "1779"]
    static func termos(_ texto: String) -> [String] {
        palavras(texto).map(Singular.forma)
    }

    /// As palavras do texto como foram escritas (normalizadas, sem as vazias), antes do singular.
    /// O prefixo da consulta precisa delas: quem ainda digita "cautelare" não acha nada no termo
    /// `cautelar`, mas acha na palavra "cautelares".
    static func palavras(_ texto: String) -> [String] {
        let caracteres = Array(Normalizacao.chave(texto))
        var termos: [String] = []
        var atual = ""

        for (i, caractere) in caracteres.enumerated() {
            if fazParteDeTermo(caractere) {
                atual.append(caractere)
            } else if caractere == hifenInvisivel {
                // Marca onde a palavra pode quebrar no fim da linha; vem junto em texto copiado.
                continue
            } else if caractere == ".", entre(caracteres, i, { $0.isNumber }) {
                // Separador de milhar em número de lei: "8.078" fica "8078", como quem digita sem ponto.
                continue
            } else if hifens.contains(caractere), entre(caracteres, i, { $0.isLetter }) {
                // "sub-rogação" fica "subrogacao", como quem digita sem hífen. Só entre letras: entre
                // dígitos o hífen é intervalo ("1.710-1.779") e juntar criaria o termo `17101779`.
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

    /// Hífen comum (U+002D), hífen (U+2010) e hífen sem quebra (U+2011). O travessão ("–", "—") não
    /// entra: é pontuação entre palavras, e continua separando.
    private static let hifens: Set<Character> = ["-", "\u{2010}", "\u{2011}"]

    /// U+00AD, o hífen invisível (*soft hyphen*).
    private static let hifenInvisivel: Character = "\u{00AD}"

    /// O caractere da posição `i` está entre dois que passam no teste?
    private static func entre(_ caracteres: [Character], _ i: Int, _ teste: (Character) -> Bool) -> Bool {
        i > 0 && i + 1 < caracteres.count && teste(caracteres[i - 1]) && teste(caracteres[i + 1])
    }
}
