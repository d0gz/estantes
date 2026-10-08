import Foundation

/// Uma estante física da biblioteca do usuário.
/// Não guarda a lista de livros: quem aponta é o livro (`Livro.estanteId`), como a chave
/// estrangeira fica no lado "muitos" de uma relação um-para-muitos no SQL.
struct Estante: Identifiable, Equatable {
    let id: UUID
    var nome: String
    let criadaEm: Date

    init(id: UUID = UUID(), nome: String, criadaEm: Date = Date()) {
        self.id = id
        self.nome = nome
        self.criadaEm = criadaEm
    }
}
