import Foundation

/// O sumário como a folha "Editar sumário" o edita: cada item com numeração, título e página como o usuário
/// digitou.
///
/// Texto, e não `String?`, pelo mesmo motivo do `RascunhoLivro`: "1.710 " com espaço precisa existir enquanto o
/// usuário digita. A limpeza e a `ValidacaoSumario` acontecem uma vez, em `montar()`.
///
/// Nada é corrigido sozinho (decisão de 20/10): mudar o nível de um item não mexe nos filhos, e apagar ou mover
/// pode deixar um salto de nível, que a validação aponta e o usuário conserta.
struct RascunhoSumario: Equatable {
    /// Um item do sumário em edição.
    struct Item: Identifiable, Equatable {
        let id: UUID
        var nivel: Int
        var numeracao: String
        var titulo: String
        var pagina: String
        /// Preservada ao editar (decisão de 20/10): diz de onde o item veio, não quem o corrigiu por último.
        let origem: OrigemItemSumario
    }

    private(set) var itens: [Item]

    init(itens: [ItemSumario]) {
        self.itens = itens.map { item in
            Item(
                id: item.id,
                nivel: item.nivel,
                numeracao: item.numeracao ?? "",
                titulo: item.titulo,
                pagina: item.pagina ?? "",
                origem: item.origem
            )
        }
    }

    // MARK: Edição

    /// Item vazio no fim, com o nível do último (quem digita em sequência costuma continuar no mesmo nível);
    /// 1 num sumário vazio. Devolve o id, para a tela abrir o item.
    @discardableResult
    mutating func adicionarNoFim() -> UUID {
        let item = Self.itemNovo(nivel: itens.last?.nivel ?? 1)
        itens.append(item)
        return item.id
    }

    /// Item vazio logo abaixo do item `id`, com o mesmo nível dele ("Próximo item" e "Inserir abaixo").
    /// `nil`, sem mudar nada, se o id não existir.
    @discardableResult
    mutating func inserir(abaixoDe id: UUID) -> UUID? {
        guard let indice = itens.firstIndex(where: { $0.id == id }) else { return nil }
        let item = Self.itemNovo(nivel: itens[indice].nivel)
        itens.insert(item, at: indice + 1)
        return item.id
    }

    /// Troca o item de mesmo id (os textos e o nível; id e origem não mudam). Id inexistente: nada muda.
    mutating func atualizar(_ item: Item) {
        guard let indice = itens.firstIndex(where: { $0.id == item.id }) else { return }
        itens[indice] = item
    }

    /// Posições como o `.onDelete` entrega.
    mutating func apagar(_ indices: IndexSet) {
        for indice in indices.reversed() where itens.indices.contains(indice) {
            itens.remove(at: indice)
        }
    }

    /// Posições como o `.onMove` entrega: `destino` conta as posições **antes** de retirar os itens
    /// (com [A, B, C], mover A para 3 dá [B, C, A]). Escrito à mão porque o `move(fromOffsets:toOffset:)`
    /// do `Array` vem do SwiftUI, e o Domínio só importa Foundation.
    mutating func mover(de origem: IndexSet, para destino: Int) {
        let validos = origem.filter { itens.indices.contains($0) }
        let movidos = validos.map { itens[$0] }
        for indice in validos.reversed() {
            itens.remove(at: indice)
        }
        // Cada item retirado antes do destino puxa o destino uma posição para cima.
        let destinoFinal = min(destino - validos.filter { $0 < destino }.count, itens.count)
        itens.insert(contentsOf: movidos, at: max(destinoFinal, 0))
    }

    // MARK: Nível

    /// O maior nível que o item pode ter sem salto: o do item anterior + 1; 1 no primeiro (e num id que não
    /// existe). É o limite do `Stepper` na tela do item.
    func nivelMaximo(id: UUID) -> Int {
        guard let indice = itens.firstIndex(where: { $0.id == id }), indice > 0 else { return 1 }
        return itens[indice - 1].nivel + 1
    }

    /// Sobe um nível se não passar do `nivelMaximo`. Um item que já passou do limite (o pai foi apagado) fica
    /// como está: rebaixá-lo seria corrigir sozinho.
    mutating func aumentarNivel(id: UUID) {
        guard let indice = itens.firstIndex(where: { $0.id == id }),
              itens[indice].nivel < nivelMaximo(id: id) else { return }
        itens[indice].nivel += 1
    }

    /// Desce um nível, no mínimo 1. Os filhos não acompanham.
    mutating func diminuirNivel(id: UUID) {
        guard let indice = itens.firstIndex(where: { $0.id == id }), itens[indice].nivel > 1 else { return }
        itens[indice].nivel -= 1
    }

    private static func itemNovo(nivel: Int) -> Item {
        Item(id: UUID(), nivel: nivel, numeracao: "", titulo: "", pagina: "", origem: .manual)
    }

    // MARK: Montagem

    /// Os itens prontos para gravar no `Livro`.
    func montar() -> [ItemSumario]? {
        itensLimpos
    }

    /// Cada texto pela `Normalizacao.textoLimpo`; numeração e página vazias viram `nil`. O título vazio vira `""`
    /// (e não some): a validação precisa apontar o item.
    private var itensLimpos: [ItemSumario] {
        itens.map { item in
            ItemSumario(
                id: item.id,
                nivel: item.nivel,
                numeracao: Normalizacao.textoLimpo(item.numeracao),
                titulo: Normalizacao.textoLimpo(item.titulo) ?? "",
                pagina: Normalizacao.textoLimpo(item.pagina),
                origem: item.origem
            )
        }
    }
}
