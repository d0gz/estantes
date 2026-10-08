import Foundation

/// Regra do nome de categoria: não pode ser vazio nem repetir o de outra categoria, sem diferenciar
/// maiúsculas e acentos ("Tributário" = "tributario").
/// Fica no Domínio, e não numa restrição de unicidade do Core Data, porque aquela diferencia acentos
/// e, no conflito, não dá à interface uma mensagem útil.
enum NomeDeCategoria {
    enum Problema: Equatable {
        case vazio
        case repetido(Categoria)
    }

    /// - Parameters:
    ///   - nome: nome digitado.
    ///   - existentes: categorias já cadastradas.
    ///   - ignorando: id da categoria sendo renomeada (pode manter o próprio nome).
    /// - Returns: o problema encontrado, ou `nil` se o nome é válido.
    static func validar(_ nome: String, existentes: [Categoria], ignorando: UUID? = nil) -> Problema? {
        let chave = Normalizacao.chave(nome)
        if chave.isEmpty { return .vazio }
        let repetida = existentes.first { $0.id != ignorando && Normalizacao.chave($0.nome) == chave }
        return repetida.map { .repetido($0) }
    }
}
