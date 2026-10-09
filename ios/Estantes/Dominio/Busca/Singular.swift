import Foundation

/// Regra mínima de plural do português: leva o termo ao singular para que "prisões" e "prisão"
/// sejam o mesmo termo da busca. Recebe o termo já normalizado (minúsculo, sem acento).
///
/// Só mexe no termo do índice e da consulta: o texto gravado no livro continua o original. Como
/// índice e consulta passam pela mesma regra, uma forma estranha ("simples" → `simple`) não
/// atrapalha; o erro possível é juntar duas palavras diferentes (um livro a mais no resultado).
/// Descartado o RSLP: ele também corta derivações ("constitucional" e "constituição" no mesmo
/// radical), o que junta conceitos jurídicos diferentes e quebra o prefixo da consulta.
enum Singular {
    /// Termos mais curtos não mudam: "as", "mes", "pais" de três letras etc.
    static let tamanhoMinimo = 4

    /// Palavras que as regras estragariam, com a forma certa. "onus" viraria `onu` (a ONU),
    /// "mais" viraria `mal`, "pais" (país) viraria `pal`; "arts" é a abreviatura de "artigos".
    static let excecoes: [String: String] = [
        "arts": "art", "civis": "civil",
        "mais": "mais", "demais": "demais", "jamais": "jamais", "pais": "pais", "cais": "cais",
        "onus": "onus", "bonus": "bonus", "virus": "virus", "lapis": "lapis",
    ]

    private static let vogais: Set<Character> = ["a", "e", "i", "o", "u"]

    /// A forma singular do termo; números, termos mistos ("cpc2015") e termos curtos voltam iguais.
    /// As regras vão da mais específica para a mais geral, e só a primeira que casa é aplicada.
    static func forma(_ termo: String) -> String {
        if let excecao = excecoes[termo] { return excecao }
        guard termo.count >= tamanhoMinimo, termo.allSatisfy(\.isLetter) else { return termo }

        if termo.hasSuffix("oes") { return trocar(3, de: termo, por: "ao") }        // prisoes → prisao
        if termo.hasSuffix("ais") { return trocar(3, de: termo, por: "al") }        // penais → penal
        if termo.hasSuffix("eis"), termo.count >= 5 {                              // imoveis → imovel
            return trocar(3, de: termo, por: "el")                                  // ("leis" fica para a última)
        }
        if termo.hasSuffix("ns") { return trocar(2, de: termo, por: "m") }          // ordens → ordem
        if termo.hasSuffix("res"), vogais.contains(antes(3, em: termo)) {           // cautelares → cautelar
            return trocar(2, de: termo, por: "")                                    // ("livres" fica para a última)
        }
        if termo.hasSuffix("zes") { return trocar(2, de: termo, por: "") }          // juizes → juiz
        if termo.hasSuffix("s"), vogais.contains(antes(1, em: termo)) {             // direitos → direito
            return trocar(1, de: termo, por: "")
        }
        return termo
    }

    /// Troca os últimos `n` caracteres.
    private static func trocar(_ n: Int, de termo: String, por final: String) -> String {
        String(termo.dropLast(n)) + final
    }

    /// O caractere logo antes dos últimos `n`.
    private static func antes(_ n: Int, em termo: String) -> Character {
        termo[termo.index(termo.endIndex, offsetBy: -(n + 1))]
    }
}
