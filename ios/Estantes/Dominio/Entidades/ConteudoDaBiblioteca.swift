import Foundation

/// A biblioteca inteira como um valor: o que se exporta, o que se lê de um arquivo e o estado final que a
/// importação grava de uma vez (`BibliotecaRepositorio.substituirBiblioteca`).
///
/// Sem `Codable`: o formato do arquivo é detalhe da camada Dados (`BibliotecaExportadaV1`), e a regra de
/// mesclagem não deve depender dele. Os livros guardam o `estanteId`, como no resto do Domínio; é o JSON v1
/// que os aninha dentro das estantes.
struct ConteudoDaBiblioteca: Equatable {
    var estantes: [Estante]
    var categorias: [Categoria]
    var livros: [Livro]

    init(estantes: [Estante] = [], categorias: [Categoria] = [], livros: [Livro] = []) {
        self.estantes = estantes
        self.categorias = categorias
        self.livros = livros
    }
}
