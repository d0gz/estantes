import SwiftUI

/// A foto da miniatura do livro (capa, folha de rosto…), em 2:3, ou a substituta: a `superficie` com um livro.
/// A foto chega depois da linha (pedida ao `CarregadorDeMiniaturas` quando a linha aparece), então a substituta
/// também é o que aparece enquanto ela carrega.
struct MiniaturaDoLivro: View {
    let livroId: UUID
    @ObservedObject var carregador: CarregadorDeMiniaturas
    /// Vem da tela (um `@ScaledMetric` lá), que também usa a largura para alinhar o separador das linhas.
    let largura: CGFloat
    @Environment(\.displayScale) private var escala
    @State private var foto: UIImage?

    var body: some View {
        MolduraDaFoto(foto: foto, largura: largura)
        // A largura no `id`: com o texto aumentado, pede de novo no tamanho novo; a versão: foto trocada no formulário.
        .task(id: Pedido(livroId: livroId, largura: largura, trocas: carregador.trocas)) {
            // O lado maior em pixels (pontos × escala da tela): nem borrada nem maior que o necessário.
            let ladoMaior = Int((largura * 1.5 * escala).rounded(.up))
            foto = await carregador.miniatura(doLivro: livroId, ladoMaior: ladoMaior)
        }
    }
}

/// A moldura 2:3 da foto do livro, ou a substituta (a `superficie` com um livro) quando não há foto. Comum à
/// miniatura das listas e ao cabeçalho do formulário.
struct MolduraDaFoto: View {
    let foto: UIImage?
    let largura: CGFloat

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
    }
}

/// O que muda o pedido da foto: outro livro, outra largura ou uma foto trocada.
private struct Pedido: Equatable {
    let livroId: UUID
    let largura: CGFloat
    let trocas: Int
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
