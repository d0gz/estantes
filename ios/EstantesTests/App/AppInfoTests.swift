import XCTest
@testable import Estantes

/// Teste mínimo da Fase 0: prova que a CI compila, roda o simulador e executa testes.
/// XCTest em vez de Swift Testing: o Swift Testing só existe a partir do Xcode 16.
final class AppInfoTests: XCTestCase {
    func testVersaoDoAppEstaDefinida() {
        XCTAssertFalse(AppInfo.versao.isEmpty)
    }
}
