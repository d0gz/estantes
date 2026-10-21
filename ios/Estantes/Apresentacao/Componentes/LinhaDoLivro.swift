import SwiftUI

/// A linha de um livro numa lista (Estante, resultados da busca): miniatura 2:3, título em serifa, volume
/// e autor · ano, e embaixo o que cada tela acrescenta (`rodape`: os chips de categoria, o local na busca).
/// Uma só para as duas telas: o mesmo livro com dois desenhos se separaria com o tempo.
struct LinhaDoLivro<Rodape: View>: View {
    let livro: Livro
    let miniaturas: CarregadorDeMiniaturas
    private let rodape: Rodape

    @Environment(\.dynamicTypeSize) private var tamanhoDoTexto
    /// Largura da miniatura: cresce com o texto grande, para acompanhar o título ao lado.
    @ScaledMetric(relativeTo: .body) private var larguraEscalada: CGFloat = 44

    init(livro: Livro, miniaturas: CarregadorDeMiniaturas, @ViewBuilder rodape: () -> Rodape) {
        self.livro = livro
        self.miniaturas = miniaturas
        self.rodape = rodape()
    }

    var body: some View {
        // Nos tamanhos de acessibilidade, o rodapé ocupa a linha inteira, embaixo da miniatura: na coluna ao lado dela,
        // um chip como "Constitucional" não cabia e quebrava no meio da palavra.
        let rodapeNaLarguraDaLinha = tamanhoDoTexto.isAccessibilitySize
        return VStack(alignment: .leading, spacing: Espaco.pequeno) {
            HStack(alignment: .top, spacing: Espaco.medio) {
                MiniaturaDoLivro(
                    livroId: livro.id, carregador: miniaturas, largura: LinhaDoLivro.largura(escalada: larguraEscalada)
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(livro.titulo)
                        .font(Fonte.tituloLivroNaLista)
                        .foregroundColor(.primary)
                        // Nos tamanhos de acessibilidade, o título inteiro: cortado em 3 linhas, sobravam duas palavras.
                        .lineLimit(tamanhoDoTexto.isAccessibilitySize ? nil : 3)
                    if let volume = LivroDetalheViewModel.textoDoVolume(livro) {
                        Text(volume)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    if let secundaria = EstanteViewModel.linhaSecundaria(livro) {
                        Text(secundaria)
                            .font(.subheadline)
                            .foregroundColor(Cor.textoSecundario)
                    }
                    if !rodapeNaLarguraDaLinha {
                        rodape
                            .padding(.top, Espaco.pequeno)
                    }
                }
                Spacer(minLength: 0)
            }
            if rodapeNaLarguraDaLinha {
                rodape
            }
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, Espaco.padrao)
        .padding(.vertical, Espaco.medio)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A linha inteira é tocável, não só o texto.
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Com teto de 1,5× (66 pt): nos tamanhos de acessibilidade ela passava de um terço da linha e espremia o título.
    fileprivate static func largura(escalada: CGFloat) -> CGFloat {
        min(escalada, 66)
    }
}

/// O divisor entre duas `LinhaDoLivro`, começando no texto (depois da miniatura), como nas listas do sistema.
struct DivisorDeLinhaDoLivro: View {
    @ScaledMetric(relativeTo: .body) private var larguraEscalada: CGFloat = 44

    var body: some View {
        Divider().padding(.leading, Espaco.padrao + LinhaDoLivro<EmptyView>.largura(escalada: larguraEscalada) + Espaco.medio)
    }
}
