import Foundation

/// Textos de quantidade das telas, no singular ou no plural.
enum Quantidade {
    /// "1 livro", "3 livros"; com artigo, "o livro", "os 3 livros" (para as frases da confirmação).
    static func livros(_ quantidade: Int, comArtigo: Bool = false) -> String {
        switch (quantidade, comArtigo) {
        case (1, false): return "1 livro"
        case (1, true): return "o livro"
        case (_, false): return "\(quantidade) livros"
        case (_, true): return "os \(quantidade) livros"
        }
    }

    /// "1 estante", "3 estantes".
    static func estantes(_ quantidade: Int) -> String {
        quantidade == 1 ? "1 estante" : "\(quantidade) estantes"
    }

    /// "1 categoria", "3 categorias".
    static func categorias(_ quantidade: Int) -> String {
        quantidade == 1 ? "1 categoria" : "\(quantidade) categorias"
    }
}
