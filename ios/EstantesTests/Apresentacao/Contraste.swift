import UIKit

/// Razão de contraste da WCAG 2 entre duas cores opacas: (L1 + 0,05) / (L2 + 0,05), com L1 a luminância da mais clara.
/// Fica no alvo de testes: o app nunca calcula contraste, só os testes conferem a paleta.
enum Contraste {
    static func razao(_ primeira: UIColor, _ segunda: UIColor) -> Double {
        let a = luminancia(primeira)
        let b = luminancia(segunda)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Luminância relativa: tira a gama do sRGB de cada canal e soma com os pesos da sensibilidade do olho
    /// (o verde pesa mais que o vermelho, e este mais que o azul).
    private static func luminancia(_ cor: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alfa: CGFloat = 0
        // `getRed` devolve false (e zera os canais) se a cor não couber em RGB: sem o guard, viraria preto calado.
        guard cor.getRed(&r, green: &g, blue: &b, alpha: &alfa) else {
            preconditionFailure("Cor sem conversão para RGB: \(cor)")
        }
        precondition(alfa == 1, "Contraste só vale para cores opacas; misture com o fundo antes.")
        func linear(_ canal: CGFloat) -> Double {
            let c = Double(canal)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
