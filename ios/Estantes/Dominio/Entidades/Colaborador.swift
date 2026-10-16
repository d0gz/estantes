import Foundation

/// Quem participa do livro sem ser autor: prefácio, tradução, organização, coordenação.
///
/// Fica separado de `autores` porque o cabeçalho do livro (regra ABNT) mostra só quem escreveu; um prefaciador
/// ali pareceria coautor. Na busca, o nome soma no campo dos autores: o usuário procura a pessoa do mesmo jeito.
struct Colaborador: Equatable {
    /// No formato dos autores: "Sobrenome, Nome" ("Bastos, Aurélio Wander").
    var nome: String
    /// O papel como vem impresso, em texto livre ("prefácio", "tradução"). Não é enum: o valor bruto iria para o
    /// JSON exportado e ficaria congelado, e um papel fora da lista não teria onde ir. Pode ser vazio.
    var papel: String
}
