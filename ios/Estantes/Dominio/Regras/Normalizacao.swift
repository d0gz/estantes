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
}
