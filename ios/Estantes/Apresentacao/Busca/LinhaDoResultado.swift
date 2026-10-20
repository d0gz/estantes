import Foundation

/// Os textos que a linha de um resultado da busca acrescenta à linha do livro: onde está o assunto
/// (item do sumário e página) e onde está o livro (estante e prateleira).
enum LinhaDoResultado {
    /// "§ 5.108 Conceito, p. 12 · Escritório · 2ª de cima".
    static func local(item: ItemSumario?, estante: String?, prateleira: String?) -> String {
        // Cada parte ausente sai junto com o seu separador: nada de "· ·" nem "·" no fim.
        [item.map(textoDoItem), preenchido(estante), preenchido(prateleira)].compactMap { $0 }.joined(separator: " · ")
    }

    /// No OU de reserva, as palavras da consulta que o livro não tem ("sem: stf, cpc"); `nil` se tem todas.
    static func ausentes(_ palavras: [String]) -> String? {
        palavras.isEmpty ? nil : "sem: " + palavras.joined(separator: ", ")
    }

    /// "§ 5.108 Conceito, p. 12", sem a numeração ou a página quando faltam.
    private static func textoDoItem(_ item: ItemSumario) -> String {
        let titulo = [preenchido(item.numeracao), item.titulo].compactMap { $0 }.joined(separator: " ")
        return preenchido(item.pagina).map { "\(titulo), p. \($0)" } ?? titulo
    }

    /// O texto aparado, ou `nil` se estiver ausente ou só tiver espaços.
    private static func preenchido(_ texto: String?) -> String? {
        let aparado = texto?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return aparado.isEmpty ? nil : aparado
    }
}
