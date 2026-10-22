import CoreData

/// Erros da persistência: pedidos que apontam para algo que não existe no banco.
enum ErroPersistencia: Error, Equatable {
    case estanteNaoEncontrada(UUID)
    case livroNaoEncontrado(UUID)
    case categoriaNaoEncontrada(UUID)
    /// Pedido para mover os livros de uma estante para ela mesma (seria apagá-los sem querer).
    case destinoInvalido(UUID)
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
            pedido.sortDescriptors = [
                NSSortDescriptor(key: #keyPath(EstanteMO.criadaEm), ascending: true),
                NSSortDescriptor(key: #keyPath(EstanteMO.id), ascending: true),
            ]
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
            pedido.predicate = Self.naEstante(estanteId)
            // COUNT no SQLite: nenhum livro é carregado na memória.
            return try contexto.count(for: pedido)
        }
    }

    func apagarEstante(id: UUID, moverLivrosPara destino: UUID?) async throws {
        // Validar antes de tocar no banco: com destino == id, o "mover" não mudaria nada e a cascata
        // apagaria todos os livros, o contrário do que o chamador pediu.
        if destino == id {
            throw ErroPersistencia.destinoInvalido(id)
        }
        try await emSegundoPlano { contexto in
            guard let estanteMO: EstanteMO = try self.buscar(EstanteMO.nomeEntidade, id: id, em: contexto) else {
                return
            }
            if let destino = destino {
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
            pedido.predicate = Self.naEstante(estanteId)
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
            Self.preencher(livroMO, com: livro, estante: estanteMO, categorias: categoriasMO, em: contexto)
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
            pedido.propertiesToFetch = [#keyPath(LivroMO.prateleira)]
            pedido.returnsDistinctResults = true
            pedido.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.naEstante(estanteId),
                NSPredicate(format: "%K != nil AND %K != ''", #keyPath(LivroMO.prateleira), #keyPath(LivroMO.prateleira)),
            ])
            return try contexto.fetch(pedido)
                .compactMap { $0[#keyPath(LivroMO.prateleira)] as? String }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }

    func fotoMiniatura(doLivro livroId: UUID) async throws -> Data? {
        try await emSegundoPlano { contexto in
            let livroMO: LivroMO? = try self.buscar(LivroMO.nomeEntidade, id: livroId, em: contexto)
            return livroMO?.fotoMiniatura
        }
    }

    func salvarFotoMiniatura(_ foto: Data?, doLivro livroId: UUID) async throws {
        try await emSegundoPlano { contexto in
            guard let livroMO: LivroMO = try self.buscar(LivroMO.nomeEntidade, id: livroId, em: contexto) else {
                throw ErroPersistencia.livroNaoEncontrado(livroId)
            }
            livroMO.fotoMiniatura = foto
            try self.gravar(contexto)
        }
    }

    // MARK: Categorias

    func categorias() async throws -> [Categoria] {
        try await emSegundoPlano { contexto in
            let pedido = NSFetchRequest<CategoriaMO>(entityName: CategoriaMO.nomeEntidade)
            pedido.sortDescriptors = [
                NSSortDescriptor(
                    key: #keyPath(CategoriaMO.nome),
                    ascending: true,
                    selector: #selector(NSString.localizedStandardCompare(_:))
                ),
                NSSortDescriptor(key: #keyPath(CategoriaMO.id), ascending: true),
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

    /// Conta a relação `livros` de cada categoria: carrega só os ids dos livros, não os livros. São poucas
    /// categorias; uma consulta agregada (`NSExpression` com `count:`) só valeria com centenas delas.
    func quantidadeDeLivrosPorCategoria() async throws -> [UUID: Int] {
        try await emSegundoPlano { contexto in
            let pedido = NSFetchRequest<CategoriaMO>(entityName: CategoriaMO.nomeEntidade)
            return try contexto.fetch(pedido).reduce(into: [:]) { $0[$1.id] = $1.livros.count }
        }
    }

    // MARK: Biblioteca inteira

    /// Um contexto e um `save`: um erro no meio sai antes do `save`, e o contexto (novo, só desta operação)
    /// é descartado sem gravar nada. Grava ou atualiza pelo id e só depois apaga o que saiu: apagar antes
    /// uma estante levaria na cascata os livros que o conteúdo muda para outra.
    func substituirBiblioteca(por conteudo: ConteudoDaBiblioteca) async throws {
        try await emSegundoPlano { contexto in
            let categoriasAntigas: [UUID: CategoriaMO] = try self.todos(CategoriaMO.nomeEntidade, em: contexto)
            let estantesAntigas: [UUID: EstanteMO] = try self.todos(EstanteMO.nomeEntidade, em: contexto)
            let livrosAntigos: [UUID: LivroMO] = try self.todos(LivroMO.nomeEntidade, em: contexto)

            var categorias: [UUID: CategoriaMO] = [:]
            for categoria in conteudo.categorias {
                let categoriaMO = categoriasAntigas[categoria.id] ?? CategoriaMO(context: contexto)
                categoriaMO.preencher(com: categoria)
                categorias[categoria.id] = categoriaMO
            }
            var estantes: [UUID: EstanteMO] = [:]
            for estante in conteudo.estantes {
                let estanteMO = estantesAntigas[estante.id] ?? EstanteMO(context: contexto)
                estanteMO.preencher(com: estante)
                estantes[estante.id] = estanteMO
            }
            for livro in conteudo.livros {
                guard let estanteMO = estantes[livro.estanteId] else {
                    throw ErroPersistencia.estanteNaoEncontrada(livro.estanteId)
                }
                let categoriasMO = try Set(livro.categoriaIds.map { id -> CategoriaMO in
                    guard let categoriaMO = categorias[id] else { throw ErroPersistencia.categoriaNaoEncontrada(id) }
                    return categoriaMO
                })
                // O livro que continua é o mesmo objeto: a `fotoMiniatura` (fora do conteúdo) fica.
                let livroMO = livrosAntigos[livro.id] ?? LivroMO(context: contexto)
                Self.preencher(livroMO, com: livro, estante: estanteMO, categorias: categoriasMO, em: contexto)
            }

            let idsDosLivros = Set(conteudo.livros.map(\.id))
            for (id, livroMO) in livrosAntigos where !idsDosLivros.contains(id) { contexto.delete(livroMO) }
            for (id, estanteMO) in estantesAntigas where estantes[id] == nil { contexto.delete(estanteMO) }
            for (id, categoriaMO) in categoriasAntigas where categorias[id] == nil { contexto.delete(categoriaMO) }
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
        // Aqui fica em texto: `T` é genérico, e todas as entidades têm o atributo `id`.
        pedido.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        pedido.fetchLimit = 1
        return try contexto.fetch(pedido).first
    }

    /// Todos os objetos de uma entidade, pelo `id`. Para a importação, que mexe na biblioteca inteira.
    private func todos<T: NSManagedObject>(_ entidade: String, em contexto: NSManagedObjectContext) throws -> [UUID: T] {
        let objetos = try contexto.fetch(NSFetchRequest<T>(entityName: entidade))
        // KVC: `T` é genérico, e todas as entidades têm o atributo `id` (como no `buscar`).
        return Dictionary(objetos.compactMap { objeto in (objeto.value(forKey: "id") as? UUID).map { ($0, objeto) } },
                          uniquingKeysWith: { primeiro, _ in primeiro })
    }

    /// Campos, estante, categorias e sumário de um livro; usado por `salvar(_ livro:)` e pela importação.
    /// O sumário é substituído em bloco: apaga os itens antigos e grava os novos com a posição.
    private static func preencher(_ livroMO: LivroMO, com livro: Livro, estante: EstanteMO,
                                  categorias: Set<CategoriaMO>, em contexto: NSManagedObjectContext) {
        livroMO.preencher(com: livro)
        livroMO.estante = estante
        livroMO.categorias = categorias
        for itemMO in livroMO.itensSumario {
            contexto.delete(itemMO)
        }
        for (posicao, item) in livro.itensSumario.enumerated() {
            let itemMO = ItemSumarioMO(context: contexto)
            itemMO.preencher(com: item, ordem: posicao)
            itemMO.livro = livroMO
        }
    }

    /// Todas as categorias pedidas, ou erro se alguma não existir (em vez de perder a etiqueta calado).
    private func categorias(ids: Set<UUID>, em contexto: NSManagedObjectContext) throws -> Set<CategoriaMO> {
        guard !ids.isEmpty else { return [] }
        let pedido = NSFetchRequest<CategoriaMO>(entityName: CategoriaMO.nomeEntidade)
        pedido.predicate = NSPredicate(format: "%K IN %@", #keyPath(CategoriaMO.id), Array(ids))
        let encontradas = try contexto.fetch(pedido)
        let idsEncontrados = Set(encontradas.map(\.id))
        if let faltando = ids.subtracting(idsEncontrados).first {
            throw ErroPersistencia.categoriaNaoEncontrada(faltando)
        }
        return Set(encontradas)
    }

    private static func pedidoDeLivrosPorTitulo() -> NSFetchRequest<LivroMO> {
        let pedido = NSFetchRequest<LivroMO>(entityName: LivroMO.nomeEntidade)
        // Títulos iguais ("Direito penal") desempatam pela data e pelo id: a ordem não muda entre leituras.
        pedido.sortDescriptors = [
            NSSortDescriptor(
                key: #keyPath(LivroMO.titulo),
                ascending: true,
                selector: #selector(NSString.localizedStandardCompare(_:))
            ),
            NSSortDescriptor(key: #keyPath(LivroMO.adicionadoEm), ascending: true),
            NSSortDescriptor(key: #keyPath(LivroMO.id), ascending: true),
        ]
        return pedido
    }

    /// `#keyPath` em vez de "estante.id" em texto: o compilador confere que o caminho existe.
    private static func naEstante(_ estanteId: UUID) -> NSPredicate {
        NSPredicate(format: "%K == %@", #keyPath(LivroMO.estante.id), estanteId as CVarArg)
    }

    private func gravar(_ contexto: NSManagedObjectContext) throws {
        if contexto.hasChanges {
            try contexto.save()
        }
    }
}
