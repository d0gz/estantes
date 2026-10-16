import Foundation

/// O ISBN como o `Livro` guarda: 13 dígitos, sem hífens. Aceita o que vem impresso (com hífens ou espaços) e o
/// ISBN-10 dos livros anteriores a 2007, que vira 13. Também vai servir à leitura do código de barras (Fase 3).
///
/// O último dígito é verificador (soma ponderada dos outros), e por isso pega a troca de um dígito:
/// - ISBN-13 (sempre começa com 978 ou 979): pesos 1, 3, 1, 3… nos 12 primeiros; o verificador completa a soma
///   até um múltiplo de 10.
/// - ISBN-10: pesos 10, 9, …, 1 nos 10 dígitos; a soma é múltiplo de 11. O verificador pode valer 10, escrito "X".
enum ISBN {
    /// "978-0-306-40615-7" → "9780306406157"; "0-306-40615-2" → "9780306406157". Letras (fora do "X" final do
    /// ISBN-10), comprimento diferente de 10 ou 13, ISBN-13 sem o prefixo 978/979 ou dígito verificador errado → `nil`.
    static func normalizar(_ texto: String) -> String? {
        let limpo = texto.filter { !separadores.contains($0) && !$0.isWhitespace }
        switch limpo.count {
        case 13:
            guard let treze = algarismos(limpo), [[9, 7, 8], [9, 7, 9]].contains(Array(treze.prefix(3))),
                  verificador13(treze.prefix(12)) == treze[12]
            else { return nil }
            return limpo
        case 10:
            guard let nove = algarismos(String(limpo.prefix(9))), let ultimo = limpo.last,
                  verificador10(nove) == valor(doVerificador10: ultimo)
            else { return nil }
            // Mesmos 9 dígitos com o prefixo 978; o verificador é recalculado pela regra do 13.
            let doze = [9, 7, 8] + nove
            return (doze + [verificador13(doze[...])]).map(String.init).joined()
        default:
            return nil
        }
    }

    /// O hífen comum e os que chegam por cópia de site ou PDF: U+2010 (hífen), U+2011 (hífen inseparável) e
    /// U+2013 (meia-risca), como no `Tokenizador`.
    private static let separadores: Set<Character> = ["-", "\u{2010}", "\u{2011}", "\u{2013}"]

    /// Só algarismos ASCII ("٣" e "½" são números para o Swift, mas não num ISBN).
    private static func algarismos(_ texto: String) -> [Int]? {
        let valores = texto.map { $0.isASCII ? $0.wholeNumberValue : nil }
        return valores.contains(nil) ? nil : valores.compactMap { $0 }
    }

    /// O último caractere do ISBN-10: um algarismo ou "X" (que vale 10).
    private static func valor(doVerificador10 caractere: Character) -> Int? {
        if caractere == "X" || caractere == "x" { return 10 }
        return algarismos(String(caractere))?.first
    }

    private static func verificador13(_ doze: ArraySlice<Int>) -> Int {
        let soma = doze.enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 0 ? 1 : 3) }
        return (10 - soma % 10) % 10
    }

    /// O valor (0…10) que completa a soma ponderada até um múltiplo de 11.
    private static func verificador10(_ nove: [Int]) -> Int {
        let soma = nove.enumerated().reduce(0) { $0 + $1.element * (10 - $1.offset) }
        return (11 - soma % 11) % 11
    }
}
