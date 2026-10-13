import SwiftUI
import UIKit

/// Cores por papel (regra 60-30-10: `fundo`, `superficie`, `destaque`). As telas usam só estas e o `.primary`;
/// nada de hex solto. O texto principal fica no `.primary` do sistema, que passa em todos os fundos.
enum Cor {
    static let fundo = Color(uiColor: Paleta.fundo)
    static let cartao = Color(uiColor: Paleta.cartao)
    static let superficie = Color(uiColor: Paleta.superficie)
    static let destaque = Color(uiColor: Paleta.destaque)
    static let sobreDestaque = Color(uiColor: Paleta.sobreDestaque)
    static let textoSecundario = Color(uiColor: Paleta.textoSecundario)
}

/// As mesmas cores em `UIColor`, com o tom claro e o escuro. Em código, e não num catálogo de cores, para o hex
/// aparecer na revisão e os testes resolverem cada modo e medirem o contraste (`PaletaTests`).
/// No escuro, o azul vibrante sobre o preto daria só 3,6:1; por isso o `#AED3FC` vira o destaque, e a superfície,
/// um azul-marinho profundo. Sobre a `superficie` clara o texto é o `.primary`: o destaque ali só como ícone ou forma
/// (3,7:1; nenhum azul vibrante chega a 4,5:1 sobre o `#AED3FC`).
enum Paleta {
    static let fundo = UIColor(claro: 0xFFFFFF, escuro: 0x000000)
    /// No claro, o cartão se separa do fundo pela sombra; no escuro, pela cor (sombra não aparece no preto).
    static let cartao = UIColor(claro: 0xFFFFFF, escuro: 0x1C1C1E)
    /// Texto e controles sobre ela vão em `.primary`: o tint global (`destaque`) daria só 3,7:1 no claro.
    static let superficie = UIColor(claro: 0xAED3FC, escuro: 0x12305A)
    static let destaque = UIColor(claro: 0x0A5FD6, escuro: 0xAED3FC)
    /// Texto ou ícone em cima do `destaque`.
    static let sobreDestaque = UIColor(claro: 0xFFFFFF, escuro: 0x1C1C1E)
    /// Substitui o `.secondary` do sistema, que dá 3,4:1 no branco e 2,9:1 sobre a `superficie`.
    static let textoSecundario = UIColor(claro: 0x4A5A62, escuro: 0xC9D6DC)
}

extension UIColor {
    /// Cor que muda com o modo claro/escuro, a partir de dois hex `0xRRGGBB`.
    convenience init(claro: UInt32, escuro: UInt32) {
        self.init { tracos in
            UIColor(hex: tracos.userInterfaceStyle == .dark ? escuro : claro)
        }
    }

    private convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
