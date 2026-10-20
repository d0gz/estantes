import SwiftUI

/// Um item do sumário como as listas o mostram: recuado pelo nível, numeração em negrito antes do título e a página
/// à direita. O mesmo no cartão do Detalhe, no sumário completo e na folha de edição.
struct ItemDoSumarioView: View {
    let nivel: Int
    let numeracao: String?
    let titulo: String
    let pagina: String?

    /// Recuo por nível; para no 5º, senão um § fundo espremeria o título numa coluna estreita.
    @ScaledMetric(relativeTo: .body) private var recuoPorNivel: CGFloat = Espaco.padrao
    private let nivelMaximoDoRecuo = 5

    init(_ item: ItemSumario) {
        nivel = item.nivel
        numeracao = item.numeracao
        titulo = item.titulo
        pagina = item.pagina
    }

    /// Na folha de edição o item ainda é texto digitado: espaços sobrando não importam aqui, vazio vira ausente.
    init(_ item: RascunhoSumario.Item) {
        nivel = item.nivel
        numeracao = Normalizacao.textoLimpo(item.numeracao)
        titulo = Normalizacao.textoLimpo(item.titulo) ?? ""
        pagina = Normalizacao.textoLimpo(item.pagina)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Espaco.pequeno) {
            textoDoItem
                .frame(maxWidth: .infinity, alignment: .leading)
            if let pagina = pagina {
                Text(pagina)
                    .monospacedDigit()
                    .foregroundColor(Cor.textoSecundario)
            }
        }
        .padding(.leading, CGFloat(min(nivel, nivelMaximoDoRecuo) - 1) * recuoPorNivel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rotuloDeAcessibilidade)
    }

    private var textoDoItem: Text {
        let corpo = titulo.isEmpty
            ? Text("Sem título").italic().foregroundColor(Cor.textoSecundario)
            : Text(titulo)
        guard let numeracao = numeracao else { return corpo }
        return Text(numeracao).bold() + Text(" ") + corpo
    }

    /// "Nível 3. § 5.108 Conceito e natureza. Página 3."
    private var rotuloDeAcessibilidade: String {
        let texto = [numeracao, titulo.isEmpty ? "Sem título" : titulo].compactMap { $0 }.joined(separator: " ")
        let paginaLida = pagina.map { " Página \($0)." } ?? ""
        return "Nível \(nivel). \(texto).\(paginaLida)"
    }
}
