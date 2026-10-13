import SwiftUI

/// A foto da miniatura do livro (capa, folha de rosto…), em 2:3, ou a substituta: a `superficie` com um livro.
/// A foto chega depois da linha (pedida ao `CarregadorDeMiniaturas` quando a linha aparece), então a substituta
/// também é o que aparece enquanto ela carrega.
struct MiniaturaDoLivro: View {
    let livroId: UUID
    let carregador: CarregadorDeMiniaturas
    /// Vem da tela (um `@ScaledMetric` lá), que também usa a largura para alinhar o separador das linhas.
    let largura: CGFloat
    @Environment(\.displayScale) private var escala
    @State private var foto: UIImage?

    var body: some View {
        ZStack {
            if let foto = foto {
                Image(uiImage: foto)
                    .resizable()
                    .scaledToFill()
            } else {
                Cor.superficie
                // `.primary` sobre a superfície: o destaque ali daria só 3,05:1 (regra da superfície, 12/10).
                Image(systemName: "book.closed")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.primary)
                    .font(.body)
            }
        }
        .frame(width: largura, height: largura * 1.5)
        .cantos(Raio.pequeno)
        .accessibilityHidden(true)
        // A largura no `id`: com o texto aumentado, pede de novo no tamanho novo.
        .task(id: Pedido(livroId: livroId, largura: largura)) {
            // O lado maior em pixels (pontos × escala da tela): nem borrada nem maior que o necessário.
            let ladoMaior = Int((largura * 1.5 * escala).rounded(.up))
            foto = await carregador.miniatura(doLivro: livroId, ladoMaior: ladoMaior)
        }
    }
}

/// O que muda o pedido da foto: outro livro ou outra largura.
private struct Pedido: Equatable {
    let livroId: UUID
    let largura: CGFloat
}

/// Estilo de botão da linha dentro de um cartão: só o véu leve do destaque ao tocar, sem encolher (encolher uma
/// linha dentro do cartão a descolaria das vizinhas). A pressão com mola fica para os cartões inteiros.
struct EstiloLinha: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Cor.destaque.opacity(configuration.isPressed ? 0.08 : 0))
            .animation(Animacao.rapida, value: configuration.isPressed)
    }
}
