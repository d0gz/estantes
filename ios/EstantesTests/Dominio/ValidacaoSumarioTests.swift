import XCTest
@testable import Estantes

/// Especificação da ValidacaoSumario (escrita na 2.1; páginas em texto e sequências desde a 2.3b).
final class ValidacaoSumarioTests: XCTestCase {
    /// Atalho para montar itens nos testes.
    private func item(_ nivel: Int, _ titulo: String = "Título", pagina: String? = nil) -> ItemSumario {
        ItemSumario(nivel: nivel, titulo: titulo, pagina: pagina)
    }

    // MARK: Casos válidos

    func testSumarioVazioEhValido() {
        let resultado = ValidacaoSumario.validar([])
        XCTAssertTrue(resultado.valido)
        XCTAssertEqual(resultado.avisos, [])
    }

    func testSumarioBemFormadoNaoTemErrosNemAvisos() {
        let itens = [
            item(1, "Parte geral"),
            item(2, "Das pessoas", pagina: "15"),
            item(3, "Da personalidade", pagina: "17"),
            item(2, "Dos bens", pagina: "80"),
            item(1, "Parte especial", pagina: "120"),
        ]
        XCTAssertEqual(ValidacaoSumario.validar(itens), ValidacaoSumario.Resultado(erros: [], avisos: []))
    }

    func testDescerVariosNiveisDeUmaVezEhPermitido() {
        let itens = [item(1), item(2), item(3), item(1)]
        XCTAssertTrue(ValidacaoSumario.validar(itens).valido)
    }

    func testPaginaIgualAAnteriorEhPermitida() {
        let itens = [item(1, pagina: "10"), item(2, pagina: "10")]
        XCTAssertEqual(ValidacaoSumario.validar(itens).avisos, [])
    }

    // MARK: Nível

    func testPrimeiroItemPrecisaSerNivel1() {
        XCTAssertEqual(ValidacaoSumario.validar([item(2)]).erros, [.saltoDeNivel(indice: 0)])
    }

    func testSubirDoisNiveisEhErro() {
        let itens = [item(1), item(3)]
        XCTAssertEqual(ValidacaoSumario.validar(itens).erros, [.saltoDeNivel(indice: 1)])
    }

    func testNivelZeroOuNegativoEhInvalido() {
        let itens = [item(1), item(0), item(-1)]
        XCTAssertEqual(
            ValidacaoSumario.validar(itens).erros,
            [.nivelInvalido(indice: 1), .nivelInvalido(indice: 2)]
        )
    }

    // MARK: Título

    func testTituloVazioOuSoComEspacosEhErro() {
        let itens = [item(1, ""), item(1, "   ")]
        XCTAssertEqual(
            ValidacaoSumario.validar(itens).erros,
            [.tituloVazio(indice: 0), .tituloVazio(indice: 1)]
        )
    }

    // MARK: Página (aviso, não erro)

    func testPaginaMenorQueAnteriorEhAvisoENaoErro() {
        let itens = [item(1, pagina: "20"), item(1, pagina: "10")]
        let resultado = ValidacaoSumario.validar(itens)
        XCTAssertTrue(resultado.valido)
        XCTAssertEqual(resultado.avisos, [.paginaMenorQueAnterior(indice: 1)])
    }

    func testItensSemPaginaSaoPuladosNaComparacao() {
        let comAviso = [item(1, pagina: "10"), item(1), item(1, pagina: "5")]
        XCTAssertEqual(ValidacaoSumario.validar(comAviso).avisos, [.paginaMenorQueAnterior(indice: 2)])

        let semAviso = [item(1, pagina: "10"), item(1), item(1, pagina: "12")]
        XCTAssertEqual(ValidacaoSumario.validar(semAviso).avisos, [])
    }

    // MARK: Vários problemas

    func testProblemasEmOrdemDeIndiceComNivelAntesDoTitulo() {
        let itens = [
            item(2, " "),             // salto (primeiro item) e título vazio
            item(1, "Ok", pagina: "9"),
            item(1, "Ok", pagina: "3"), // aviso de página
        ]
        let resultado = ValidacaoSumario.validar(itens)
        XCTAssertEqual(resultado.erros, [.saltoDeNivel(indice: 0), .tituloVazio(indice: 0)])
        XCTAssertEqual(resultado.avisos, [.paginaMenorQueAnterior(indice: 2)])
        XCTAssertFalse(resultado.valido)
    }
    
    func testComparaComAPaginaImediatamenteAnterior() {
           // monta: páginas 10, 50, 20 — o 20 é menor que o 50 (o item anterior)
           let itens = [item(1, pagina: "10"), item(1, pagina: "50"), item(1, pagina: "20")]
           // chama
           let resultado = ValidacaoSumario.validar(itens)
           // confere: aviso no índice 2 (o terceiro item)
           XCTAssertEqual(resultado.avisos, [.paginaMenorQueAnterior(indice: 2)])
       }

    // MARK: Página por sequência (2.3b)

    func testRomanosDoPrefacioSeguidosDeArabicosNaoGeramAviso() {
        let itens = [item(1, pagina: "XI"), item(1, pagina: "XII"), item(1, pagina: "1"), item(1, pagina: "2")]
        XCTAssertEqual(ValidacaoSumario.validar(itens).avisos, [])
    }

    func testRomanoMenorQueORomanoAnteriorEhAviso() {
        let itens = [item(1, pagina: "XII"), item(1, pagina: "xi")]
        XCTAssertEqual(ValidacaoSumario.validar(itens).avisos, [.paginaMenorQueAnterior(indice: 1)])
    }

    func testTrocarDeArabicoParaRomanoNaoGeraAviso() {
        // Ex.: índice remissivo numerado em romanos depois do corpo do livro.
        let itens = [item(1, pagina: "245"), item(1, pagina: "I")]
        XCTAssertEqual(ValidacaoSumario.validar(itens).avisos, [])
    }

    func testPaginaQueNaoEhNumeroEhPuladaNaComparacao() {
        let itens = [item(1, pagina: "20"), item(1, pagina: "s/n"), item(1, pagina: "10")]
        XCTAssertEqual(ValidacaoSumario.validar(itens).avisos, [.paginaMenorQueAnterior(indice: 2)])
    }

    func testIntervaloComparaPeloInicio() {
        let itens = [item(1, pagina: "245-246"), item(1, pagina: "247")]
        XCTAssertEqual(ValidacaoSumario.validar(itens).avisos, [])
    }

    func testNumeroDaPaginaDoItem() {
        XCTAssertEqual(item(1, pagina: "XII").numeroDaPagina, .romano(12))
        XCTAssertEqual(item(1, pagina: "245").numeroDaPagina, .arabico(245))
        XCTAssertNil(item(1, pagina: "s/n").numeroDaPagina)
        XCTAssertNil(item(1).numeroDaPagina)
    }
}
