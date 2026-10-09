import XCTest
@testable import Estantes

/// Mede o motor de busca sobre a biblioteca e as consultas de referência (passo 6 da 2.3).
/// Para ler o relatório: `grep "\[referencia\]" "$TMPDIR/estantes-xcodebuild-test.log"`.
final class ConsultasDeReferenciaTests: XCTestCase {
    private let motor = BibliotecaDeReferencia.motor()

    // MARK: - O conjunto em si

    func testBibliotecaDeReferenciaEhConsistente() {
        let fichas = BibliotecaDeReferencia.fichas
        XCTAssertEqual(Set(fichas.map(\.chave)).count, fichas.count, "chave repetida")
        XCTAssertEqual(Set(fichas.map(\.livro.id)).count, fichas.count, "UUID repetido")

        let livros = Dictionary(uniqueKeysWithValues: fichas.map { ($0.chave, $0.livro) })
        for consulta in ConsultasDeReferencia.todas {
            guard let livro = livros[consulta.esperado] else {
                XCTFail("\"\(consulta.texto)\": a ficha \"\(consulta.esperado)\" não existe")
                continue
            }
            if let esperado = consulta.itemEsperado {
                XCTAssertTrue(
                    livro.itensSumario.contains { $0.numeracao == esperado || $0.titulo == esperado },
                    "\"\(consulta.texto)\": o item \"\(esperado)\" não existe em \(consulta.esperado)"
                )
            }
        }
    }

    // MARK: - Relatório

    /// Só imprime: uma linha por consulta e os agregados das consultas de ajuste.
    func testRelatorioDasConsultas() {
        let avaliacao = MetricasDeBusca.avaliar(
            ConsultasDeReferencia.todas, motor: motor, ids: BibliotecaDeReferencia.ids
        )
        for (indice, medicao) in avaliacao.medicoes.enumerated() {
            print(linha(numero: indice + 1, medicao))
        }
        print(String(
            format: "[referencia] AJUSTE (%d): top1 %.3f · top3 %.3f · MRR %.3f · item certo %@",
            avaliacao.deAjuste.count, avaliacao.top1, avaliacao.top3, avaliacao.mrr,
            avaliacao.itemCerto.map { String(format: "%.3f", $0) } ?? "–"
        ))
    }

    private func linha(numero: Int, _ medicao: MedicaoDeConsulta) -> String {
        let consulta = medicao.consulta
        let tipo = consulta.tipo == .sonda ? "sonda" : "ajuste"
        let posicao = medicao.posicao.map { "\($0)º" } ?? "ausente"
        let nota = medicao.nota.map { String(format: "%.3f", $0) } ?? "–"
        var texto = "[referencia] #\(numero) \(tipo) \(consulta.caso.rawValue) \"\(consulta.texto)\" → "
            + "\(consulta.esperado): \(posicao) (nota \(nota))"
        if let esperado = consulta.itemEsperado {
            let mostrado = medicao.itemMostrado.map { $0.numeracao ?? $0.titulo } ?? "nenhum"
            let marca = medicao.itemCerto == true ? "✓" : "✗"
            texto += " · item \(marca) esperado \"\(esperado)\", mostrado \"\(mostrado)\""
        }
        // Quem ficou à frente, para entender o erro.
        if medicao.posicao != 1 {
            let primeiros = motor.buscar(consulta.texto).prefix(3).map {
                "\(chave(de: $0.livro.id)) \(String(format: "%.3f", $0.nota))"
            }
            texto += " · primeiros: " + (primeiros.isEmpty ? "nenhum resultado" : primeiros.joined(separator: " | "))
        }
        return texto
    }

    private func chave(de id: UUID) -> String {
        BibliotecaDeReferencia.fichas.first { $0.livro.id == id }?.chave ?? id.uuidString
    }
}
