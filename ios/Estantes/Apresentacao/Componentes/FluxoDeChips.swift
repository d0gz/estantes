import SwiftUI

/// Põe os chips lado a lado e desce para a linha seguinte quando o próximo não cabe, como palavras num parágrafo.
/// Cada chip fica com a largura do próprio nome; só um chip mais largo que a linha inteira (texto grande) recebe a
/// largura disponível e quebra o nome dentro dele, entre palavras. Substitui grades de colunas fixas, que cortavam
/// os nomes letra a letra com texto grande.
/// `Layout` é do iOS 16: dispensa medir os chips com `GeometryReader` e `PreferenceKey`.
struct FluxoDeChips: Layout {
    var espaco: CGFloat = Espaco.pequeno

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largura = proposal.width ?? .infinity
        let posicoes = organizar(subviews, largura: largura)
        let direita = posicoes.map { $0.origem.x + $0.tamanho.width }.max() ?? 0
        let base = posicoes.map { $0.origem.y + $0.tamanho.height }.max() ?? 0
        return CGSize(width: proposal.width ?? direita, height: base)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (indice, posicao) in organizar(subviews, largura: bounds.width).enumerated() {
            subviews[indice].place(
                at: CGPoint(x: bounds.minX + posicao.origem.x, y: bounds.minY + posicao.origem.y),
                proposal: ProposedViewSize(posicao.tamanho)
            )
        }
    }

    /// Quais chips (pelos índices) vão em cada linha. Separada do SwiftUI para ser testada com números.
    static func linhas(larguras: [CGFloat], espaco: CGFloat, larguraDisponivel: CGFloat) -> [[Int]] {
        var linhas: [[Int]] = []
        var atual: [Int] = []
        var ocupada: CGFloat = 0
        for (indice, largura) in larguras.enumerated() {
            if !atual.isEmpty && ocupada + espaco + largura > larguraDisponivel {
                linhas.append(atual)
                atual = []
            }
            ocupada = atual.isEmpty ? largura : ocupada + espaco + largura
            atual.append(indice)
        }
        if !atual.isEmpty { linhas.append(atual) }
        return linhas
    }

    private func organizar(_ subviews: Subviews, largura: CGFloat) -> [(origem: CGPoint, tamanho: CGSize)] {
        let tamanhos = subviews.map { subview -> CGSize in
            let ideal = subview.sizeThatFits(.unspecified)
            guard ideal.width > largura else { return ideal }
            return subview.sizeThatFits(ProposedViewSize(width: largura, height: nil))
        }
        var posicoes = Array(repeating: (origem: CGPoint.zero, tamanho: CGSize.zero), count: subviews.count)
        var y: CGFloat = 0
        for linha in Self.linhas(larguras: tamanhos.map(\.width), espaco: espaco, larguraDisponivel: largura) {
            var x: CGFloat = 0
            let altura = linha.map { tamanhos[$0].height }.max() ?? 0
            for indice in linha {
                // Centrado na vertical dentro da linha (um chip com nome em duas linhas fica mais alto).
                posicoes[indice] = (CGPoint(x: x, y: y + (altura - tamanhos[indice].height) / 2), tamanhos[indice])
                x += tamanhos[indice].width + espaco
            }
            y += altura + espaco
        }
        return posicoes
    }
}
