import Foundation

/// Montagem das dependências: o único lugar que sabe qual implementação de cada porta o app usa.
///
/// As telas não conhecem o Core Data: pedem aqui um ViewModel pronto, que recebe o repositório
/// pelo `init`. Trocar o banco (ou usar um em memória nas capturas) muda só este arquivo.
/// É um valor criado uma vez no `EstantesApp`, não um singleton.
struct Dependencias {
    let repositorio: BibliotecaRepositorio

    /// O app de verdade: Core Data gravando em disco. Lança erro se o banco não abrir.
    static func producao() throws -> Dependencias {
        let persistencia = try PersistenceController()
        return Dependencias(repositorio: BibliotecaRepositorioCoreData(persistencia: persistencia))
    }

    /// Core Data em memória (`/dev/null`): começa vazio e nada chega ao disco.
    /// Usado nos previews e nas capturas do simulador.
    static func emMemoria() throws -> Dependencias {
        let persistencia = try PersistenceController(emMemoria: true)
        return Dependencias(repositorio: BibliotecaRepositorioCoreData(persistencia: persistencia))
    }

    // MARK: Fábricas de ViewModels

    @MainActor
    func fazerInicioViewModel() -> InicioViewModel {
        InicioViewModel(repositorio: repositorio)
    }

    @MainActor
    func fazerEstanteViewModel(estante: Estante) -> EstanteViewModel {
        EstanteViewModel(estante: estante, repositorio: repositorio)
    }

    @MainActor
    func fazerLivroDetalheViewModel(livroId: UUID) -> LivroDetalheViewModel {
        LivroDetalheViewModel(livroId: livroId, repositorio: repositorio)
    }
}
