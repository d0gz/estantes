import Foundation

/// Regra da importação: o conteúdo lido de um arquivo é coerente? O JSON pode estar bem formado e mesmo assim
/// contradizer o modelo; um arquivo assim é rejeitado inteiro, antes de qualquer gravação (decisão de 21/10).
///
/// O app sempre grava dados que passam por estas regras; um arquivo que não passa foi editado fora do app.
enum ValidacaoDaBiblioteca {
    enum Problema: Equatable {
        /// Duas estantes, duas categorias ou dois livros com o mesmo UUID.
        case idRepetido(UUID)
        /// O livro cita uma categoria que o arquivo não traz.
        case categoriaInexistente(livro: UUID, categoria: UUID)
        /// Nome vazio ou repetido (sem diferenciar maiúsculas e acentos), pela mesma regra da tela.
        case nomeDeCategoria(NomeDeCategoria.Problema)
        /// O `isbn13` não está na forma que o app grava (13 dígitos válidos, sem hífens).
        case isbnInvalido(livro: UUID)
        /// O sumário tem erro na `ValidacaoSumario` (avisos não contam).
        case sumarioInvalido(livro: UUID)
    }

    /// - Returns: o primeiro problema encontrado, ou `nil` se o conteúdo pode ser importado.
    static func validar(_ conteudo: ConteudoDaBiblioteca) -> Problema? {
        // Os itens do sumário ficam de fora: o repositório os recria a cada gravação, sem buscar pelo id.
        if let repetido = primeiroRepetido(conteudo.estantes.map(\.id))
            ?? primeiroRepetido(conteudo.categorias.map(\.id))
            ?? primeiroRepetido(conteudo.livros.map(\.id)) {
            return .idRepetido(repetido)
        }
        for (indice, categoria) in conteudo.categorias.enumerated() {
            if let problema = NomeDeCategoria.validar(categoria.nome, existentes: Array(conteudo.categorias[..<indice])) {
                return .nomeDeCategoria(problema)
            }
        }
        let idsDasCategorias = Set(conteudo.categorias.map(\.id))
        for livro in conteudo.livros {
            if let sumida = livro.categoriaIds.sorted(by: { $0.uuidString < $1.uuidString })
                .first(where: { !idsDasCategorias.contains($0) }) {
                return .categoriaInexistente(livro: livro.id, categoria: sumida)
            }
            if let isbn = livro.isbn13, ISBN.normalizar(isbn) != isbn {
                return .isbnInvalido(livro: livro.id)
            }
            if !ValidacaoSumario.validar(livro.itensSumario).valido {
                return .sumarioInvalido(livro: livro.id)
            }
        }
        return nil
    }

    private static func primeiroRepetido(_ ids: [UUID]) -> UUID? {
        var vistos = Set<UUID>()
        return ids.first { !vistos.insert($0).inserted }
    }
}
