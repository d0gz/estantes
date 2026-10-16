import UIKit

/// Os tons de uma cor de categoria no chip: contorno e ícone (`viva`), nome (`texto`) e fundo (`veu`, sempre
/// usado a `Paleta.opacidadeDoVeu` sobre o cartão).
struct TonsDeCategoria {
    let viva: UIColor
    let texto: UIColor
    let veu: UIColor
}

extension Paleta {
    static let opacidadeDoVeu = 0.15

    /// Hex congelados a partir das cores do sistema no iOS 16, onde o chip foi aprovado (captura
    /// `EstiloCategorias_1.5`): no iOS 26 as cores do sistema podem mudar, e o `PaletaTests` mediria outra cor que a
    /// da tela (Histórico de 16/10 no PLANO).
    /// - Claro: viva = cor do sistema; texto = o mesmo matiz escurecido só até ~4,6:1 sobre o véu.
    /// - Escuro: viva e texto = variante de "Aumentar contraste" (mais clara); véu = a cor normal do escuro.
    /// O rosa é próprio (matiz 331°): o `systemPink` (349°) ficava a 14° do vermelho.
    static func categoria(_ cor: CorCategoria) -> TonsDeCategoria {
        switch cor {
        case .vermelho: return tons(viva: 0xFF3B30, texto: 0xCE0B00, forte: 0xFF6961, veuEscuro: 0xFF453A)
        case .laranja: return tons(viva: 0xFF9500, texto: 0x9E5C00, forte: 0xFFB340, veuEscuro: 0xFF9F0A)
        case .amarelo: return tons(viva: 0xFFCC00, texto: 0x876C00, forte: 0xFFD426, veuEscuro: 0xFFD60A)
        case .verde: return tons(viva: 0x34C759, texto: 0x207C38, forte: 0x30DB5B, veuEscuro: 0x30D158)
        case .menta: return tons(viva: 0x00C7BE, texto: 0x007873, forte: 0x63E6E2, veuEscuro: 0x63E6E2)
        // O texto no alto contraste (`#7D7AFF`) dava 4,3:1 sobre o véu; `#8582FF` é ele clareado só até ~4,6:1
        // (escolhido na captura `EstiloCategorias_1.6`). O contorno continua no `#7D7AFF`.
        case .indigo:
            return tons(viva: 0x5856D6, texto: 0x5654D6, forte: 0x7D7AFF, veuEscuro: 0x5E5CE6, textoEscuro: 0x8582FF)
        case .roxo: return tons(viva: 0xAF52DE, texto: 0x9D2BD7, forte: 0xDA8FFF, veuEscuro: 0xBF5AF2)
        case .rosa: return tons(viva: 0xFF2D92, texto: 0xCB0062, forte: 0xFF7AC0, veuEscuro: 0xFF7AC0)
        case .marrom: return tons(viva: 0xA2845E, texto: 0x7D6648, forte: 0xB59469, veuEscuro: 0xAC8E68)
        case .cinza: return tons(viva: 0x8E8E93, texto: 0x636366, forte: 0xAEAEB2, veuEscuro: 0x8E8E93)
        }
    }

    /// `textoEscuro` só quando o alto contraste não passa como texto sobre o véu.
    private static func tons(
        viva: UInt32, texto: UInt32, forte: UInt32, veuEscuro: UInt32, textoEscuro: UInt32? = nil
    ) -> TonsDeCategoria {
        TonsDeCategoria(
            viva: UIColor(claro: viva, escuro: forte),
            texto: UIColor(claro: texto, escuro: textoEscuro ?? forte),
            veu: UIColor(claro: viva, escuro: veuEscuro)
        )
    }
}
