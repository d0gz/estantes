import SwiftUI

/// Botão da ação principal (Salvar, Adicionar), no lugar do `.borderedProminent`: esse desenha o rótulo sempre
/// branco, que no escuro fica sobre o `#AED3FC` e ficou ilegível no catálogo. Aqui o rótulo é `sobreDestaque`,
/// o par que o `PaletaTests` mede, e a pressão tem a mesma mola do vidro.
struct EstiloPrincipal: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Principal(rotulo: configuration.label, pressionado: configuration.isPressed)
    }
}

/// View à parte porque o `@Environment` é lido numa `View`, não no `ButtonStyle`.
private struct Principal<Rotulo: View>: View {
    let rotulo: Rotulo
    let pressionado: Bool
    @Environment(\.isEnabled) private var habilitado

    var body: some View {
        rotulo
            .font(.body.weight(.semibold))
            .foregroundColor(Cor.sobreDestaque)
            .padding(.horizontal, Espaco.padrao)
            .padding(.vertical, Espaco.medio)
            .background(Cor.destaque)
            .cantos(Raio.medio)
            // Pressionado: escurece um pouco em vez de piscar.
            .brightness(pressionado ? -0.08 : 0)
            .opacity(habilitado ? 1 : 0.4)
            .pressao(pressionado)
    }
}
