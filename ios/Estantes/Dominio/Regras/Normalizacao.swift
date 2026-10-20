import Foundation

/// Normalização de texto para comparar e buscar sem depender de maiúsculas, acentos e espaços.
/// A busca usa esta normalização dentro do `Tokenizador`, que acrescenta a quebra em termos e as palavras vazias.
enum Normalizacao {
    /// Minúsculas, sem acentos, sem espaços nas pontas e com espaços internos reduzidos a um.
    /// "  Direito   Tributário " → "direito tributario"
    static func chave(_ texto: String) -> String {
        texto
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Sem espaços nas pontas, e cada sequência de espaços ou quebras de linha no meio vira um espaço só (texto
    /// colado de um PDF); vazio vira `nil` (o Domínio não guarda texto em branco). Mantém maiúsculas e acentos:
    /// é o texto que se grava, não a chave de comparação.
    /// "  Capítulo \n  II " → "Capítulo II"
    static func textoLimpo(_ texto: String) -> String? {
        let limpo = texto.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return limpo.isEmpty ? nil : limpo
    }
}
