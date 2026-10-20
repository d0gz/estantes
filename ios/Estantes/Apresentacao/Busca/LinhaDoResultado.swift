import Foundation

/// Os textos que a linha de um resultado da busca acrescenta à linha do livro, em duas partes: onde está o assunto
/// (item do sumário e página, o motivo da busca) e onde está o livro (estante e prateleira, mais discreto).
enum LinhaDoResultado {
    /// "§ 5.108 Conceito, p. 12"; `nil` sem item (o livro casou pelo título, autor...).
    static func item(_ item: ItemSumario?) -> String? {
        item.map(textoDoItem)
    }

    /// "Escritório · 2ª de cima"; parte ausente sai junto com o separador, e sem nenhuma, `nil`.
    static func lugar(estante: String?, prateleira: String?) -> String? {
        let partes = [preenchido(estante), preenchido(prateleira)].compactMap { $0 }
        return partes.isEmpty ? nil : partes.joined(separator: " · ")
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
