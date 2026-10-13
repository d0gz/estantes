import SwiftUI

/// Cartão de uma estante na grade do Inicio: ícone no destaque, nome em serifa e a contagem de livros.
/// Fundo `cartao` com sombra leve (a `superficie` fica para seleção e chips). Recebe só textos, para o catálogo
/// de estilo mostrar o mesmo cartão sem precisar de uma `Estante`.
struct CartaoDeEstante: View {
    let nome: String
    let detalhe: String

    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.minimo) {
            Image(systemName: "books.vertical.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(Cor.destaque)
                .font(.title3)
                .accessibilityHidden(true)
            // Nome e contagem presos à base: os cartões da mesma linha ficam alinhados mesmo com nomes de duas linhas.
            Spacer(minLength: Espaco.medio)
            Text(nome)
                .font(Fonte.tituloEstante)
                .foregroundColor(.primary)
                .lineLimit(2)
            Text(detalhe)
                .font(.subheadline)
                .foregroundColor(Cor.textoSecundario)
        }
        // 96: altura que deixa o cartão com cara de bloco com nome de uma linha. Com texto grande o conteúdo passa
        // disso e o cartão cresce sozinho, sem espaço morto.
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(Espaco.medio)
        .background(Cor.cartao)
        .cantos(Raio.grande)
        .sombraSuave()
        .accessibilityElement(children: .combine)
    }
}

/// Estilo de botão do cartão (o cartão já desenha o próprio fundo): pressão com mola e um véu leve do destaque,
/// que continua sendo o sinal de toque com "Reduzir movimento". Véu, não escurecer: no escuro o cartão `#1C1C1E`
/// mal escurece.
struct EstiloCartao: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: Raio.grande, style: .continuous)
                    .fill(Cor.destaque.opacity(configuration.isPressed ? 0.08 : 0))
            }
            .pressao(configuration.isPressed)
    }
}

/// Ilustração do estado vazio: lombadas esmaecidas na `superficie`. Só desenho, sem "+": um "+" em círculo tem
/// forma de botão, e a tela já tem a ação de criar (HIG: no estado vazio, a imagem informa e há no máximo uma ação).
struct IlustracaoEstanteVazia: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: Espaco.pequeno) {
            ForEach([70, 90, 60, 80], id: \.self) { altura in
                Cor.superficie.frame(width: 22, height: CGFloat(altura)).cantos(4)
            }
        }
        .accessibilityHidden(true)
    }
}
