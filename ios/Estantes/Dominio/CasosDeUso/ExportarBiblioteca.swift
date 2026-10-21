import Foundation

/// Gera o arquivo de backup da biblioteca inteira (sem fotos: elas ficam para o .zip da Fase 5).
struct ExportarBiblioteca {
    let repositorio: BibliotecaRepositorio
    let codificador: CodificadorDeBiblioteca

    func executar() async throws -> Data {
        try codificador.codificar(try await repositorio.conteudoInteiro())
    }
}

extension BibliotecaRepositorio {
    /// A biblioteca inteira como um valor: para exportar e para mesclar com um arquivo. Extensão, e não um
    /// método da porta, porque só junta leituras que a porta já tem.
    func conteudoInteiro() async throws -> ConteudoDaBiblioteca {
        ConteudoDaBiblioteca(
            estantes: try await estantes(),
            categorias: try await categorias(),
            livros: try await todosOsLivros()
        )
    }
}
