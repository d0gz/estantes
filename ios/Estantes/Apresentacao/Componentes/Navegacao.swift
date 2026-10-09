import SwiftUI

/// Valor empurrado na pilha de navegação para abrir o detalhe de um livro.
/// Um tipo próprio em vez de `UUID` solto: `navigationDestination(for: UUID.self)` pegaria qualquer
/// UUID que alguma tela empurrasse, e o nome deixa claro para onde a rota leva.
struct RotaDoLivro: Hashable {
    let livroId: UUID
}

extension View {
    /// Roda `acao` toda vez que a tela volta a aparecer, menos na primeira (que fica com o `.task`).
    /// Na pilha de navegação o `.task` não roda de novo ao voltar de uma tela filha; é aqui que a tela
    /// relê o banco para mostrar o que mudou lá (livro apagado, editado...).
    func aoVoltar(_ acao: @escaping () async -> Void) -> some View {
        modifier(AoVoltar(acao: acao))
    }
}

private struct AoVoltar: ViewModifier {
    let acao: () async -> Void
    @State private var jaApareceu = false

    func body(content: Content) -> some View {
        content.onAppear {
            if jaApareceu {
                Task { await acao() }
            }
            jaApareceu = true
        }
    }
}
