import SwiftUI

/// Botão sem fundo próprio (a foto do Detalhe, os chips de categoria): encolhe com a mola ao tocar e escurece de leve
/// (só o sinal parado, com "Reduzir movimento", pelo `.pressao`).
struct EstiloPressao: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pressao(configuration.isPressed)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
