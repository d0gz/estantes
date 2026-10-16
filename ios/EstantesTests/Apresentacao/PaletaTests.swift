import UIKit
import XCTest
@testable import Estantes

/// Todo par texto/fundo da paleta passa no piso de 4,5:1 da WCAG (texto normal), no claro e no escuro; o destaque
/// sobre a `superficie` só aparece como ícone ou forma e segue o piso de 3:1 (WCAG 1.4.11, elementos que não são texto).
/// Pega um hex trocado que quebre o contraste, inclusive só num dos modos; não pega pares fora desta lista.
final class PaletaTests: XCTestCase {
    private let piso = 4.5
    private let pisoSemTexto = 3.0

    private let fundos: [(nome: String, cor: UIColor)] = [
        ("fundo", Paleta.fundo),
        ("cartao", Paleta.cartao),
        ("superficie", Paleta.superficie),
    ]

    /// Fundos em que o destaque pode ser texto (links, botões sem fundo); na `superficie` ele só é ícone ou forma.
    private var fundosDeTexto: [(nome: String, cor: UIColor)] {
        fundos.filter { $0.nome != "superficie" }
    }

    /// O que pode ir escrito sobre qualquer fundo. `label` é o `.primary` do SwiftUI.
    private let textos: [(nome: String, cor: UIColor)] = [
        ("texto", .label),
        ("textoSecundario", Paleta.textoSecundario),
    ]

    func testTextoSobreCadaFundoNoClaro() {
        conferirTextosSobreFundos(em: .light)
    }

    func testTextoSobreCadaFundoNoEscuro() {
        conferirTextosSobreFundos(em: .dark)
    }

    func testDestaqueComoTextoSobreFundoECartaoNosDoisModos() {
        for modo in [UIUserInterfaceStyle.light, .dark] {
            for fundo in fundosDeTexto {
                let razao = Contraste.razao(resolver(Paleta.destaque, modo), resolver(fundo.cor, modo))
                XCTAssertGreaterThanOrEqual(razao, piso, "destaque × \(fundo.nome) (\(nome(modo)))")
            }
        }
    }

    func testDestaqueComoIconeSobreASuperficieNosDoisModos() {
        for modo in [UIUserInterfaceStyle.light, .dark] {
            let razao = Contraste.razao(resolver(Paleta.destaque, modo), resolver(Paleta.superficie, modo))
            XCTAssertGreaterThanOrEqual(razao, pisoSemTexto, "destaque × superficie (\(nome(modo)))")
        }
    }

    /// O vermelho das ações destrutivas ("Apagar livro", erros do formulário) é texto sobre o fundo e o cartão.
    /// O `systemRed` (`#FF3B30`) dá ~3,6:1 no branco e reprovaria.
    func testPerigoComoTextoSobreFundoECartaoNosDoisModos() {
        for modo in [UIUserInterfaceStyle.light, .dark] {
            for fundo in fundosDeTexto {
                let razao = Contraste.razao(resolver(Paleta.perigo, modo), resolver(fundo.cor, modo))
                XCTAssertGreaterThanOrEqual(razao, piso, "perigo × \(fundo.nome) (\(nome(modo)))")
            }
        }
    }

    func testSobreDestaqueEmCimaDoDestaqueNosDoisModos() {
        for modo in [UIUserInterfaceStyle.light, .dark] {
            let razao = Contraste.razao(resolver(Paleta.sobreDestaque, modo), resolver(Paleta.destaque, modo))
            XCTAssertGreaterThanOrEqual(razao, piso, "sobreDestaque × destaque (\(nome(modo)))")
        }
    }

    // MARK: Categorias

    /// O texto do chip vai sobre o véu da cor (a 15%) em cima do cartão. Mede todas as cores do enum, então uma cor
    /// nova sem tom de texto bom reprova aqui sem ninguém lembrar de pôr o par numa lista. O contorno e o ícone ficam
    /// fora: são decorativos (o nome escrito diz a categoria), e o amarelo vivo daria 1,5:1 no branco.
    func testTextoDoChipSobreOVeuDeCadaCorNosDoisModos() {
        for cor in CorCategoria.allCases {
            let tons = Paleta.categoria(cor)
            for modo in [UIUserInterfaceStyle.light, .dark] {
                let veu = misturar(resolver(tons.veu, modo), a: Paleta.opacidadeDoVeu, sobre: resolver(Paleta.cartao, modo))
                let razao = Contraste.razao(resolver(tons.texto, modo), veu)
                XCTAssertGreaterThanOrEqual(
                    razao, piso,
                    "texto × véu de \(cor.rawValue) (\(nome(modo))): \(String(format: "%.2f", razao))"
                )
            }
        }
    }

    /// Os tons de texto no claro aprovados na captura `EstiloCategorias_1.5` (protótipo do catálogo, 12/10) e o do
    /// cinza proposto em 16/10. Pega um hex copiado errado que ainda passasse no contraste.
    func testTextoDoChipNoClaroEhOAprovado() {
        let aprovados: [CorCategoria: UInt32] = [
            .vermelho: 0xCE0B00, .laranja: 0x9E5C00, .amarelo: 0x876C00, .verde: 0x207C38, .menta: 0x007873,
            .indigo: 0x5654D6, .roxo: 0x9D2BD7, .rosa: 0xCB0062, .marrom: 0x7D6648, .cinza: 0x636366,
        ]
        for cor in CorCategoria.allCases {
            XCTAssertEqual(hex(resolver(Paleta.categoria(cor).texto, .light)), aprovados[cor], cor.rawValue)
        }
    }

    /// Mistura alfa simples em sRGB (como o SwiftUI compõe uma cor com opacidade sobre outra).
    private func misturar(_ cor: UIColor, a alfa: Double, sobre fundo: UIColor) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        cor.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        fundo.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let a = CGFloat(alfa)
        return UIColor(red: r1 * a + r2 * (1 - a), green: g1 * a + g2 * (1 - a), blue: b1 * a + b2 * (1 - a), alpha: 1)
    }

    private func hex(_ cor: UIColor) -> UInt32 {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        cor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UInt32(round(r * 255)) << 16 | UInt32(round(g * 255)) << 8 | UInt32(round(b * 255))
    }

    private func conferirTextosSobreFundos(em modo: UIUserInterfaceStyle) {
        for fundo in fundos {
            for texto in textos {
                let razao = Contraste.razao(resolver(texto.cor, modo), resolver(fundo.cor, modo))
                XCTAssertGreaterThanOrEqual(
                    razao, piso,
                    "\(texto.nome) × \(fundo.nome) (\(nome(modo))): \(String(format: "%.2f", razao))"
                )
            }
        }
    }

    private func resolver(_ cor: UIColor, _ modo: UIUserInterfaceStyle) -> UIColor {
        cor.resolvedColor(with: UITraitCollection(userInterfaceStyle: modo))
    }

    private func nome(_ modo: UIUserInterfaceStyle) -> String {
        modo == .dark ? "escuro" : "claro"
    }
}
