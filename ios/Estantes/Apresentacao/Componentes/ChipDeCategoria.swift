import SwiftUI

/// Etiqueta de uma categoria (desenho "A" do Estilo 0): contorno e ícone na cor viva, véu da cor sobre o cartão e
/// nome no tom de texto da paleta (`Paleta.categoria`). Só desenha: o toque fica com quem usa o chip.
struct ChipDeCategoria: View {
    private enum Conteudo {
        case categoria(nome: String, tons: TonsDeCategoria)
        case fantasma
    }

    private let conteudo: Conteudo

    init(_ categoria: Categoria) {
        conteudo = .categoria(nome: categoria.nome, tons: Paleta.categoria(categoria.cor))
    }

    private init(fantasma: Void) {
        conteudo = .fantasma
    }

    /// "+ Categoria": convite para o livro sem categoria. É uma ação, não uma etiqueta: sem cor de categoria,
    /// contorno tracejado no texto secundário.
    static let fantasma = ChipDeCategoria(fantasma: ())

    var body: some View {
        switch conteudo {
        case let .categoria(nome, tons):
            let viva = Color(uiColor: tons.viva)
            forma(icone: "tag", texto: nome, corDoIcone: viva, corDoTexto: Color(uiColor: tons.texto))
                // O primeiro `background` fica por cima: véu da cor sobre o fundo do cartão.
                .background(Color(uiColor: tons.veu).opacity(Paleta.opacidadeDoVeu), in: Capsule())
                .background(Cor.cartao, in: Capsule())
                .overlay(Capsule().strokeBorder(viva, lineWidth: 1))
        case .fantasma:
            forma(icone: "plus", texto: "Categoria", corDoIcone: Cor.textoSecundario, corDoTexto: Cor.textoSecundario)
                .overlay(Capsule().strokeBorder(Cor.textoSecundario, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }

    private func forma(icone: String, texto: String, corDoIcone: Color, corDoTexto: Color) -> some View {
        HStack(spacing: Espaco.minimo) {
            Image(systemName: icone).foregroundColor(corDoIcone)
            Text(texto).foregroundColor(corDoTexto)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, Espaco.medio)
        .padding(.vertical, Espaco.pequeno)
    }
}
