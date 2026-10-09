import Foundation

/// O número de uma página impressa e a sequência a que pertence. Livros antigos numeram o prefácio
/// e a introdução em romanos ("XI", "XII") e recomeçam em arábicos no corpo ("1", "2"): o caso do
/// enum é a sequência, e o valor associado é o número dentro dela.
///
/// O `ItemSumario` guarda a página como texto (o que está impresso); este tipo é derivado dele,
/// para comparar páginas na `ValidacaoSumario`. A conversão de romanos também vai servir ao parser
/// da folha de rosto ("Tomo XLVIII"), na Fase 3.
enum NumeroDePagina: Equatable {
    case arabico(Int)
    case romano(Int)

    /// "245" → `.arabico(245)`; "xii" → `.romano(12)`; "XI-XII" → `.romano(11)` (num intervalo vale o
    /// início). Texto que não é um número de página ("s/n", "12a", "IIII") → `nil`.
    static func interpretar(_ texto: String) -> NumeroDePagina? {
        let inicio = texto
            .split(whereSeparator: { separadoresDeIntervalo.contains($0) })
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !inicio.isEmpty else { return nil }

        if inicio.allSatisfy({ $0.isASCII && $0.isNumber }) {
            guard let numero = Int(inicio), numero > 0 else { return nil }
            return .arabico(numero)
        }
        return inteiro(romano: inicio).map { .romano($0) }
    }

    /// "XLVIII" → 48. Aceita minúsculas. Só a forma canônica: "IIII", "IC" e "VX" → `nil`.
    ///
    /// Soma da esquerda para a direita e subtrai o símbolo menor que o seguinte (IV = 5 − 1), em O(n).
    /// A soma sozinha aceitaria lixo de OCR ("IIIII" = 5), por isso a conferência de ida e volta:
    /// o número convertido de novo para romano tem de dar o mesmo texto.
    static func inteiro(romano texto: String) -> Int? {
        let simbolos = Array(texto.uppercased())
        let valores = simbolos.compactMap { valorDoSimbolo[$0] }
        guard !valores.isEmpty, valores.count == simbolos.count else { return nil }

        var total = 0
        for (i, valor) in valores.enumerated() {
            if i + 1 < valores.count, valor < valores[i + 1] {
                total -= valor
            } else {
                total += valor
            }
        }
        guard let canonico = romano(total), canonico == String(simbolos) else { return nil }
        return total
    }

    /// 48 → "XLVIII". Fora de 1...3999 (o que os sete símbolos representam) → `nil`.
    /// Guloso: tira o maior valor da tabela que ainda cabe, incluindo os pares subtrativos (CM, XC, IV...).
    static func romano(_ numero: Int) -> String? {
        guard (1...3999).contains(numero) else { return nil }
        var resto = numero
        var texto = ""
        for (valor, simbolo) in tabelaCanonica {
            while resto >= valor {
                texto += simbolo
                resto -= valor
            }
        }
        return texto
    }

    /// Hífen, hífen Unicode, travessão curto e longo: "XI-XII", "245–246".
    private static let separadoresDeIntervalo: Set<Character> = ["-", "‐", "‑", "–", "—"]

    private static let valorDoSimbolo: [Character: Int] = [
        "I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000,
    ]

    private static let tabelaCanonica: [(Int, String)] = [
        (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
        (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
    ]
}
