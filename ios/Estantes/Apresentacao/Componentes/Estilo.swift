import SwiftUI

/// Escala de espaçamento em passos de 4 pt. `padrao` (16) é a margem do iOS. Valores fixos: onde um espaço
/// precisar crescer com o texto grande, a tela usa `@ScaledMetric`.
enum Espaco {
    static let minimo: CGFloat = 4
    static let pequeno: CGFloat = 8
    static let medio: CGFloat = 12
    static let padrao: CGFloat = 16
    static let grande: CGFloat = 24
    static let enorme: CGFloat = 32
}

/// Raios dos cantos: `pequeno` em chips, campos e capas; `medio` em botões; `grande` em cartões.
enum Raio {
    static let pequeno: CGFloat = 8
    static let medio: CGFloat = 12
    static let grande: CGFloat = 20
}

/// Só as fontes que fogem do sistema: serifa (New York) nos títulos de livros e estantes, para dar cara de livro.
/// O resto usa os estilos do sistema direto (`.body`, `.caption`...). Partindo de um estilo de texto,
/// as duas crescem com o Dynamic Type.
enum Fonte {
    static let tituloLivro = Font.system(.title2, design: .serif).weight(.semibold)
    static let tituloEstante = Font.system(.title3, design: .serif).weight(.semibold)
}

/// Molas com nome, para o movimento ser o mesmo em todas as telas.
enum Animacao {
    /// Transições: entrar, sair, expandir.
    static let suave = Animation.spring(response: 0.35, dampingFraction: 0.85)
    /// Resposta ao toque (pressão de botão): mais curta e quase sem balanço.
    static let rapida = Animation.spring(response: 0.25, dampingFraction: 0.9)
    /// Com "Reduzir movimento": curta e sem balanço, no lugar das molas.
    static let esmaecer = Animation.easeInOut(duration: 0.2)

    /// A regra única do "Reduzir movimento": a mola pedida, ou `esmaecer` se a opção estiver ligada.
    static func escolher(_ mola: Animation, reduzirMovimento: Bool) -> Animation {
        reduzirMovimento ? esmaecer : mola
    }
}

extension AnyTransition {
    /// Entrada e saída de conteúdo: esmaece e sobe um pouco; com "Reduzir movimento", só esmaece (deslocar é movimento).
    static func entrada(reduzirMovimento: Bool) -> AnyTransition {
        reduzirMovimento ? .opacity : .opacity.combined(with: .offset(y: 8))
    }
}

extension View {
    /// Recorta com canto contínuo (o "squircle" do iOS), que o `cornerRadius` comum não usa.
    func cantos(_ raio: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: raio, style: .continuous))
    }

    /// Anima as mudanças de `valor` com a mola `suave`, ou com `esmaecer` se o "Reduzir movimento" estiver ligado.
    func animacaoSuave<Valor: Equatable>(valor: Valor) -> some View {
        modifier(AnimacaoSuave(valor: valor))
    }

    /// Encolhe com a mola `rapida` enquanto pressionado; com "Reduzir movimento", não encolhe. Por isso cada estilo de
    /// botão tem também um sinal parado de pressão (véu no vidro e no cartão, brilho no principal).
    func pressao(_ pressionado: Bool) -> some View {
        modifier(Pressao(pressionado: pressionado))
    }

    /// Sombra leve de cartão no modo claro; no escuro, nenhuma (a separação vem da cor do `cartao`).
    func sombraSuave() -> some View {
        modifier(SombraSuave())
    }
}

private struct AnimacaoSuave<Valor: Equatable>: ViewModifier {
    let valor: Valor
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    func body(content: Content) -> some View {
        content.animation(Animacao.escolher(Animacao.suave, reduzirMovimento: reduzirMovimento), value: valor)
    }
}

private struct Pressao: ViewModifier {
    let pressionado: Bool
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressionado && !reduzirMovimento ? 0.97 : 1)
            .animation(Animacao.escolher(Animacao.rapida, reduzirMovimento: reduzirMovimento), value: pressionado)
    }
}

private struct SombraSuave: ViewModifier {
    @Environment(\.colorScheme) private var esquema

    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(esquema == .dark ? 0 : 0.08), radius: 12, x: 0, y: 4)
    }
}
