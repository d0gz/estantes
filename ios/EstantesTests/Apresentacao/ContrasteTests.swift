import UIKit
import XCTest

/// A fórmula de contraste da WCAG, conferida contra valores publicados fora daqui.
final class ContrasteTests: XCTestCase {
    private let cinza777 = UIColor(red: 0x77 / 255, green: 0x77 / 255, blue: 0x77 / 255, alpha: 1)

    func testPretoSobreBrancoDaVinteEUm() {
        XCTAssertEqual(Contraste.razao(.black, .white), 21, accuracy: 0.01)
    }

    /// Exemplo clássico do verificador da WebAIM: #777777 sobre branco dá 4,48:1 (reprova por pouco).
    func testCinza777SobreBrancoDaQuatroQuarentaEOito() {
        XCTAssertEqual(Contraste.razao(cinza777, .white), 4.48, accuracy: 0.01)
    }

    func testAOrdemDasCoresNaoMuda() {
        XCTAssertEqual(Contraste.razao(.white, cinza777), 4.48, accuracy: 0.01)
    }
}
