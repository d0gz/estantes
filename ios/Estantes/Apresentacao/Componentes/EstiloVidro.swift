import SwiftUI

/// Botão de "vidro" para elementos que flutuam sobre o conteúdo (câmera, barra de filtros): imita no iOS 16 o
/// Liquid Glass do iOS 26, cujas APIs (`glassEffect`, `.buttonStyle(.glass)`) não compilam no Xcode 14.2.
/// Material translúcido que pega a cor do que está atrás, brilho fino na borda e, ao tocar, encolhe um pouco
/// e se preenche com um véu do destaque. Forma de cápsula: com conteúdo quadrado, vira círculo.
///
/// O ícone é `.primary`, não `destaque`: o material acompanha o modo claro/escuro (não a capa atrás), e o
/// `.primary` acompanha o material; o azul sumia sobre capa escura no claro e sobre capa clara no escuro.
/// Limite conhecido: o contraste depende do que está atrás, e nenhum teste o mede (conferência no catálogo).
struct EstiloVidro: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Vidro(rotulo: configuration.label, pressionado: configuration.isPressed)
    }
}

/// View à parte porque o `@Environment` é lido numa `View`, não no `ButtonStyle`.
private struct Vidro<Rotulo: View>: View {
    let rotulo: Rotulo
    let pressionado: Bool

    var body: some View {
        rotulo
            .foregroundColor(.primary)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Cor.destaque.opacity(pressionado ? 0.15 : 0))
                }
            }
            .overlay {
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .white.opacity(0.1)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            }
            .contentShape(Capsule())
            // Encolher é movimento: com "Reduzir movimento" fica só o véu.
            .pressao(pressionado)
    }
}
