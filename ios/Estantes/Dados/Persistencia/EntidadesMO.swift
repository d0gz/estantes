import CoreData

// Classes do Core Data, uma por entidade do modelo `Estantes.xcdatamodeld`.
//
// Escritas à mão (codegen "Manual/None") e com o sufixo MO (managed object) porque a geração automática
// criaria classes `Livro`, `Estante`... com o mesmo nome das structs do Domínio, visíveis no app inteiro.
// Só este diretório as conhece: o resto do app usa as structs (ver `Conversao.swift`).
//
// `@objc(Nome)` fixa o nome Objective-C da classe, que é o que o modelo procura em `representedClassName`;
// sem ele, o nome real seria `Estantes.LivroMO` (com o módulo) e o Core Data não acharia a classe.
// `@NSManaged` diz ao compilador que o Core Data fornece o armazenamento do atributo em tempo de execução.

@objc(EstanteMO)
final class EstanteMO: NSManagedObject {
    static let nomeEntidade = "Estante"

    @NSManaged var id: UUID
    @NSManaged var nome: String
    @NSManaged var criadaEm: Date
    @NSManaged var livros: Set<LivroMO>
}

@objc(LivroMO)
final class LivroMO: NSManagedObject {
    static let nomeEntidade = "Livro"

    @NSManaged var id: UUID
    @NSManaged var titulo: String
    @NSManaged var subtitulo: String?
    /// Um autor por linha (`FormatoPersistido.separadorAutores`).
    @NSManaged var autores: String
    @NSManaged var editora: String?
    @NSManaged var edicao: String?
    /// `NSNumber?` e não `Int`: um número "escalar" do Core Data não pode ficar vazio.
    @NSManaged var ano: NSNumber?
    @NSManaged var isbn13: String?
    @NSManaged var paginas: NSNumber?
    @NSManaged var cddir: String?
    /// Níveis unidos por `FormatoPersistido.separadorCddir`.
    @NSManaged var cddirCaminho: String
    @NSManaged var urn: String?
    /// `OrigemLivro.rawValue`.
    @NSManaged var origem: String
    @NSManaged var prateleira: String?
    /// Fora da struct `Livro`; só o repositório lê e grava (Allows External Storage no modelo).
    @NSManaged var fotoCapa: Data?
    @NSManaged var adicionadoEm: Date

    /// Obrigatória no modelo: salvar um livro sem estante falha na validação do Core Data.
    @NSManaged var estante: EstanteMO
    @NSManaged var categorias: Set<CategoriaMO>
    /// Sem ordem própria (não é `NSOrderedSet`): a ordem está no atributo `ordem` de cada item.
    @NSManaged var itensSumario: Set<ItemSumarioMO>
}

@objc(ItemSumarioMO)
final class ItemSumarioMO: NSManagedObject {
    static let nomeEntidade = "ItemSumario"

    @NSManaged var id: UUID
    /// Posição do item no array `Livro.itensSumario` (0 = primeiro).
    @NSManaged var ordem: Int32
    @NSManaged var nivel: Int32
    @NSManaged var numeracao: String?
    @NSManaged var titulo: String
    @NSManaged var pagina: NSNumber?
    /// `OrigemItemSumario.rawValue`.
    @NSManaged var origem: String
    @NSManaged var livro: LivroMO
}

@objc(CategoriaMO)
final class CategoriaMO: NSManagedObject {
    static let nomeEntidade = "Categoria"

    @NSManaged var id: UUID
    @NSManaged var nome: String
    /// `CorCategoria.rawValue`.
    @NSManaged var cor: String
    @NSManaged var livros: Set<LivroMO>
}
