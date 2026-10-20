import SwiftUI

/// O sumário inteiro, empurrado pelo "Ver sumário completo (N)" do Detalhe. Só leitura: editar é pela folha.
struct SumarioCompletoView: View {
    let itens: [ItemSumario]

    var body: some View {
        List(itens) { item in
            ItemDoSumarioView(item)
        }
        .listStyle(.plain)
        .navigationTitle("Sumário")
        .navigationBarTitleDisplayMode(.inline)
    }
}
