import CoreData

/// Erros da persistência: pedidos que apontam para algo que não existe no banco.
enum ErroPersistencia: Error, Equatable {
    case estanteNaoEncontrada(UUID)
    case livroNaoEncontrado(UUID)
    case categoriaNaoEncontrada(UUID)
}

/// Implementa a porta `BibliotecaRepositorio` com Core Data.
///
/// Cada operação roda num contexto de fundo novo (`newBackgroundContext` + `perform`): a tela não trava,
/// e cada operação começa sem objetos antigos em cache. Entra e sai só struct; os `…MO` não saem daqui.
final class BibliotecaRepositorioCoreData: BibliotecaRepositorio {
    private let container: NSPersistentContainer

    init(persistencia: PersistenceController) {
        container = persistencia.container
    }

    // MARK: Estantes

    func estantes() async throws -> [Estante] {
        try await emSegundoPlano { contexto in
            let pedido = NSFetchRequest<EstanteMO>(entityName: EstanteMO.nomeEntidade)
            pedido.sortDescriptors = [NSSortDescriptor(key: "criadaEm", ascending: true)]
            return try contexto.fetch(pedido).map { $0.paraDominio() }
        }
    }

    func salvar(_ estante: Estante) async throws {
        try await emSegundoPlano { contexto in
            let estanteMO: EstanteMO = try self.buscar(EstanteMO.nomeEntidade, id: estante.id, em: contexto)
                ?? EstanteMO(context: contexto)
            estanteMO.preencher(com: estante)
            try self.gravar(contexto)
        }
    }

    func quantidadeDeLivros(naEstante estanteId: UUID) async throws -> Int {
        try await emSegundoPlano { contexto in
            let pedido = NSFetchRequest<LivroMO>(entityName: LivroMO.nomeEntidade)
            pedido.predicate = NSPredicate(format: "estante.id == %@", estanteId as CVarArg)
            // COUNT no SQLite: nenhum livro é carregado na memória.
            return try contexto.count(for: pedido)
        }
    }

    func apagarEstante(id: UUID, moverLivrosPara destino: UUID?) async throws {
        try await emSegundoPlano { contexto in
            guard let estanteMO: EstanteMO = try self.buscar(EstanteMO.nomeEntidade, id: id, em: contexto) else {
                return
            }
            if let destino = destino, destino != id {
                guard let destinoMO: EstanteMO = try self.buscar(EstanteMO.nomeEntidade, id: destino, em: contexto) else {
                    throw ErroPersistencia.estanteNaoEncontrada(destino)
                }
                // Trocar a estante de cada livro tira o livro da estante antiga (relação inversa),
                // então a cascata não o alcança.
                for livroMO in estanteMO.livros {
                    livroMO.estante = destinoMO
                }
            }
            contexto.delete(estanteMO)
            try self.gravar(contexto)
        }
    }

    // MARK: Livros

    func livros(naEstante estanteId: UUID) async throws -> [Livro] {
        try await emSegundoPlano { contexto in
            let pedido = Self.pedidoDeLivrosPorTitulo()
            pedido.predicate = NSPredicate(format: "estante.id == %@", estanteId as CVarArg)
            return try contexto.fetch(pedido).map { $0.paraDominio() }
        }
    }

    func todosOsLivros() async throws -> [Livro] {
        try await emSegundoPlano { contexto in
            try contexto.fetch(Self.pedidoDeLivrosPorTitulo()).map { $0.paraDominio() }
        }
    }

    func livro(id: UUID) async throws -> Livro? {
        try await emSegundoPlano { contexto in
            let livroMO: LivroMO? = try self.buscar(LivroMO.nomeEntidade, id: id, em: contexto)
            return livroMO?.paraDominio()
        }
    }

    func salvar(_ livro: Livro) async throws {
        try await emSegundoPlano { contexto in
            guard let estanteMO: EstanteMO = try self.buscar(EstanteMO.nomeEntidade, id: livro.estanteId, em: contexto) else {
                throw ErroPersistencia.estanteNaoEncontrada(livro.estanteId)
            }
            let categoriasMO = try self.categorias(ids: livro.categoriaIds, em: contexto)

            let livroMO: LivroMO = try self.buscar(LivroMO.nomeEntidade, id: livro.id, em: contexto)
                ?? LivroMO(context: contexto)
            livroMO.preencher(com: livro)
            livroMO.estante = estanteMO
            livroMO.categorias = categoriasMO

            // O sumário é substituído em bloco: apaga os itens antigos e grava os novos com a posição.
            for itemMO in livroMO.itensSumario {
                contexto.delete(itemMO)
            }
            for (posicao, item) in livro.itensSumario.enumerated() {
                let itemMO = ItemSumarioMO(context: contexto)
                itemMO.preencher(com: item, ordem: posicao)
                itemMO.livro = livroMO
            }
            try self.gravar(contexto)
        }
    }

    func apagarLivro(id: UUID) async throws {
        try await emSegundoPlano { contexto in
            guard let livroMO: LivroMO = try self.buscar(LivroMO.nomeEntidade, id: id, em: contexto) else {
                return
            }
            contexto.delete(livroMO)
            try self.gravar(contexto)
        }
    }

    func prateleiras(naEstante estanteId: UUID) async throws -> [String] {
        try await emSegundoPlano { contexto in
            // Pedido de "dicionários": o SQLite devolve só a coluna `prateleira`, já sem repetição
            // (SELECT DISTINCT), em vez de objetos `LivroMO` inteiros.
            let pedido = NSFetchRequest<NSDictionary>(entityName: LivroMO.nomeEntidade)
            pedido.resultType = .dictionaryResultType
            pedido.propertiesToFetch = ["prateleira"]
            pedido.returnsDistinctResults = true
            pedido.predicate = NSPredicate(
                format: "estante.id == %@ AND prateleira != nil AND prateleira != ''",
                estanteId as CVarArg
            )
            return try contexto.fetch(pedido)
                .compactMap { $0["prateleira"] as? String }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }

    func fotoCapa(doLivro livroId: UUID) async throws -> Data? {
        try await emSegundoPlano { contexto in
            let livroMO: LivroMO? = try self.buscar(LivroMO.nomeEntidade, id: livroId, em: contexto)
            return livroMO?.fotoCapa
        }
    }

    func salvarFotoCapa(_ foto: Data?, doLivro livroId: UUID) async throws {
        try await emSegundoPlano { contexto in
            guard let livroMO: LivroMO = try self.buscar(LivroMO.nomeEntidade, id: livroId, em: contexto) else {
                throw ErroPersistencia.livroNaoEncontrado(livroId)
            }
            livroMO.fotoCapa = foto
            try self.gravar(contexto)
        }
    }

    // MARK: Categorias

    func categorias() async throws -> [Categoria] {
        try await emSegundoPlano { contexto in
            let pedido = NSFetchRequest<CategoriaMO>(entityName: CategoriaMO.nomeEntidade)
            pedido.sortDescriptors = [
                NSSortDescriptor(key: "nome", ascending: true, selector: #selector(NSString.localizedStandardCompare(_:)))
            ]
            return try contexto.fetch(pedido).map { $0.paraDominio() }
        }
    }

    func salvar(_ categoria: Categoria) async throws {
        try await emSegundoPlano { contexto in
            let categoriaMO: CategoriaMO = try self.buscar(CategoriaMO.nomeEntidade, id: categoria.id, em: contexto)
                ?? CategoriaMO(context: contexto)
            categoriaMO.preencher(com: categoria)
            try self.gravar(contexto)
        }
    }

    func apagarCategoria(id: UUID) async throws {
        try await emSegundoPlano { contexto in
            guard let categoriaMO: CategoriaMO = try self.buscar(CategoriaMO.nomeEntidade, id: id, em: contexto) else {
                return
            }
            // Regra nullify no modelo: os livros só perdem a etiqueta.
            contexto.delete(categoriaMO)
            try self.gravar(contexto)
        }
    }

    // MARK: Auxiliares

    /// Roda `trabalho` na fila de um contexto de fundo novo e devolve o resultado com `await`.
    /// Os `…MO` só podem ser tocados dentro do `perform` (cada contexto tem a sua fila).
    private func emSegundoPlano<T>(_ trabalho: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        let contexto = container.newBackgroundContext()
        return try await contexto.perform {
            try trabalho(contexto)
        }
    }

    /// Procura um objeto pelo `id` (o UUID do Domínio, não o `NSManagedObjectID`).
    private func buscar<T: NSManagedObject>(_ entidade: String, id: UUID, em contexto: NSManagedObjectContext) throws -> T? {
        let pedido = NSFetchRequest<T>(entityName: entidade)
        pedido.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        pedido.fetchLimit = 1
        return try contexto.fetch(pedido).first
    }

    /// Todas as categorias pedidas, ou erro se alguma não existir (em vez de perder a etiqueta calado).
    private func categorias(ids: Set<UUID>, em contexto: NSManagedObjectContext) throws -> Set<CategoriaMO> {
        guard !ids.isEmpty else { return [] }
        let pedido = NSFetchRequest<CategoriaMO>(entityName: CategoriaMO.nomeEntidade)
        pedido.predicate = NSPredicate(format: "id IN %@", Array(ids))
        let encontradas = try contexto.fetch(pedido)
        let idsEncontrados = Set(encontradas.map(\.id))
        if let faltando = ids.subtracting(idsEncontrados).first {
            throw ErroPersistencia.categoriaNaoEncontrada(faltando)
        }
        return Set(encontradas)
    }

    private static func pedidoDeLivrosPorTitulo() -> NSFetchRequest<LivroMO> {
        let pedido = NSFetchRequest<LivroMO>(entityName: LivroMO.nomeEntidade)
        pedido.sortDescriptors = [
            NSSortDescriptor(key: "titulo", ascending: true, selector: #selector(NSString.localizedStandardCompare(_:)))
        ]
        return pedido
    }

    private func gravar(_ contexto: NSManagedObjectContext) throws {
        if contexto.hasChanges {
            try contexto.save()
        }
    }
}
