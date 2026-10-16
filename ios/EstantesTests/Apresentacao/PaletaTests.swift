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
