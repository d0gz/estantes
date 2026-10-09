import CoreData

// Conversão entre as classes do Core Data (`…MO`) e as structs do Domínio.
// É o ÚNICO lugar do app onde as duas se encontram.
//
// [eu escrevo] — Ricardo implementa as funções abaixo. As assinaturas e os separadores já estão prontos;
// os corpos atuais são só "tampões" que compilam, para os testes ficarem vermelhos (TDD).
// Testes: EstantesTests/Dados/BibliotecaRepositorioCoreDataTests.swift
//
// Divisão do trabalho:
// - `paraDominio()`: lê o objeto do Core Data e monta a struct.
// - `preencher(com:)`: copia os campos da struct para o objeto (inclusive o `id`).
//   Só ATRIBUTOS: as relações (estante, categorias, itens do sumário) e a `fotoCapa` são do repositório,
//   que precisa buscar outros objetos no contexto para ligá-los.
//
// Dicas:
// - `Int?` → `NSNumber?`: `ano.map { NSNumber(value: $0) }`; de volta: `ano?.intValue`.
// - `Int` ↔ `Int32`: `Int32(item.nivel)` e `Int(nivel)`.
// - Enum ↔ String: `origem.rawValue`; de volta: `OrigemLivro(rawValue: origem)` devolve um opcional.
//   Pense no que fazer se o texto gravado não for um caso conhecido.
// - `[String]` ↔ String: `joined(separator:)` e `components(separatedBy:)`.
//   O teste `testLivroMinimoMantemOpcionaisNil` confere um livro sem autores.
// - Os itens do sumário chegam num `Set` (sem ordem): ordene pelo atributo `ordem` antes de converter.
// - Das categorias, o `Livro` só guarda os ids.

/// Como listas de texto viram uma String só no Core Data.
enum FormatoPersistido {
    /// Um autor por linha: os nomes já têm vírgula ("Sobrenome, Nome").
    static let separadorAutores = "\n"
    /// Decidido no PLANO.md: "Direito > Direito civil > Contratos".
    static let separadorCddir = " > "
}

extension EstanteMO {
    func paraDominio() -> Estante {
        Estante(nome: "")
    }

    func preencher(com estante: Estante) {
    }
}

extension CategoriaMO {
    func paraDominio() -> Categoria {
        Categoria(nome: "", cor: .cinza)
    }

    func preencher(com categoria: Categoria) {
    }
}

extension ItemSumarioMO {
    func paraDominio() -> ItemSumario {
        ItemSumario(nivel: 0, titulo: "")
    }

    /// - Parameter ordem: posição do item no array do livro.
    func preencher(com item: ItemSumario, ordem: Int) {
    }
}

extension LivroMO {
    func paraDominio() -> Livro {
        Livro(estanteId: UUID(), titulo: "")
    }

    func preencher(com livro: Livro) {
    }
}
