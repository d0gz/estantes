import CoreData

/// Monta a pilha do Core Data: modelo → coordenador → arquivo SQLite.
///
/// Sem singleton (`static let shared`): o `App/Dependencias` cria um e o entrega ao repositório;
/// os testes criam um em memória por teste.
final class PersistenceController {
    /// O modelo é carregado uma vez só. Se cada container carregasse o seu, o Core Data veria várias
    /// entidades disputando a mesma classe (`LivroMO`...), avisaria e poderia ligar o objeto à errada.
    /// É uma constante em memória, não um serviço global.
    static let modelo: NSManagedObjectModel = {
        guard
            let url = Bundle(for: PersistenceController.self).url(forResource: "Estantes", withExtension: "momd"),
            let modelo = NSManagedObjectModel(contentsOf: url)
        else {
            fatalError("Modelo Estantes.momd não encontrado no bundle do app")
        }
        return modelo
    }()

    let container: NSPersistentContainer

    /// - Parameters:
    ///   - emMemoria: grava em `/dev/null`. Continua sendo SQLite (o mesmo motor da produção),
    ///     só que nada chega ao disco; cada container começa vazio. Usado nos testes e previews.
    ///   - arquivo: outro arquivo SQLite no lugar do padrão (`Application Support/Estantes.sqlite`).
    ///     Usado no teste que fecha e reabre o banco.
    init(emMemoria: Bool = false, arquivo: URL? = nil) throws {
        container = NSPersistentContainer(name: "Estantes", managedObjectModel: Self.modelo)
        if emMemoria {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else if let arquivo = arquivo {
            container.persistentStoreDescriptions.first?.url = arquivo
        }

        // Por padrão o carregamento é síncrono: quando a função volta, o store já está pronto (ou falhou).
        var erroAoCarregar: Error?
        container.loadPersistentStores { _, erro in
            erroAoCarregar = erro
        }
        if let erroAoCarregar = erroAoCarregar {
            throw erroAoCarregar
        }

        // O repositório grava em contextos de fundo; isto faz o contexto da tela enxergar as gravações.
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
