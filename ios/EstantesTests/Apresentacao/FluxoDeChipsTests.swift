import XCTest
@testable import Estantes

/// A conta das linhas do `FluxoDeChips`: quais chips vão em cada linha, dadas as larguras. Os esperados foram
/// resolvidos à mão (somando larguras e espaços). Não cobre as posições em y nem o desenho (vistos nas capturas).
final class FluxoDeChipsTests: XCTestCase {
    /// 50 + 8 + 60 = 118 cabe em 130; + 8 + 40 = 166 não cabe; 40 + 8 + 80 = 128 cabe.
    func testQuebraQuandoOProximoChipComOEspacoNaoCabe() {
        XCTAssertEqual(FluxoDeChips.linhas(larguras: [50, 60, 40, 80], espaco: 8, larguraDisponivel: 130), [[0, 1], [2, 3]])
    }

    /// 60 + 8 + 62 = 130: encostar na borda ainda cabe.
    func testChipQueEncostaNaBordaFicaNaMesmaLinha() {
        XCTAssertEqual(FluxoDeChips.linhas(larguras: [60, 62], espaco: 8, larguraDisponivel: 130), [[0, 1]])
    }

    /// Com texto grande um chip pode passar da linha inteira: vai sozinho, sem uma linha vazia antes.
    func testChipMaisLargoQueALinhaVaiSozinho() {
        XCTAssertEqual(FluxoDeChips.linhas(larguras: [200, 30], espaco: 8, larguraDisponivel: 130), [[0], [1]])
    }

    func testSemChipsNaoHaLinhas() {
        XCTAssertEqual(FluxoDeChips.linhas(larguras: [], espaco: 8, larguraDisponivel: 130), [])
    }
}
