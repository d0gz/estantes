import Foundation

/// Cor de uma categoria, como identificador de uma paleta fixa.
/// O Domínio não conhece `Color` (SwiftUI): a Apresentação converte cada caso num par de tons
/// (claro e escuro) com contraste conferido. O valor bruto vai para o Core Data e para o JSON.
/// Sem azul, ciano e teal: se confundiriam com o destaque do app. A ordem é a da paleta (desempate da cor sugerida).
enum CorCategoria: String, CaseIterable {
    case vermelho
    case laranja
    case amarelo
    case verde
    case menta
    case indigo
    case roxo
    case rosa
    case marrom
    case cinza
}

/// Etiqueta de assunto escolhida pelo usuário, ligada a vários livros (muitos-para-muitos).
/// O nome é único sem diferenciar maiúsculas nem acentos (ver `NomeDeCategoria`).
struct Categoria: Identifiable, Equatable {
    let id: UUID
    var nome: String
    var cor: CorCategoria

    init(id: UUID = UUID(), nome: String, cor: CorCategoria) {
        self.id = id
        self.nome = nome
        self.cor = cor
    }
}
