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

    // MARK: - Varredura dos parâmetros

    /// Um parâmetro de cada vez (descida por coordenadas), na ordem do conflito mais provável para o
    /// menos provável. O peso do título fica fixo em 3 como âncora: multiplicar todos os pesos por c
    /// equivale a dividir o `k1` por c, então só as proporções entre os pesos importam.
    private static let passos: [(nome: String, valores: [Double], aplicar: (ParametrosBM25F, Double) -> ParametrosBM25F)] = [
        ("peso sumario", [0.25, 0.5, 0.75, 1, 1.5, 2], { $0.comPeso(.sumario, $1) }),
        ("b sumario", [0, 0.25, 0.5, 0.75, 1], { $0.comB(.sumario, $1) }),
        ("peso subtitulo", [1, 1.5, 2, 2.5, 3], { $0.comPeso(.subtitulo, $1) }),
        ("peso categorias", [0.5, 1, 1.5, 2, 3], { $0.comPeso(.categorias, $1) }),
        ("peso cddirCaminho", [0.5, 1, 1.5, 2, 3], { $0.comPeso(.cddirCaminho, $1) }),
        ("peso autores", [0.25, 0.5, 1, 1.5], { $0.comPeso(.autores, $1) }),
        ("k1", [0.8, 1.2, 1.6, 2.0], { $0.comK1($1) }),
        ("b titulo", [0, 0.25, 0.5, 0.75], { $0.comB(.titulo, $1) }),
        ("b subtitulo", [0, 0.25, 0.5, 0.75], { $0.comB(.subtitulo, $1) })
    ]

    /// Só imprime (`[varredura]`). Escolha: nenhuma troca pode piorar o item certo (restrição); entre as
    /// que respeitam, maior MRR; no empate, maior top 1; ainda empatado, fica o valor atual (só troca com
    /// ganho real). Para numa volta sem nenhuma troca, ou depois de 2 voltas.
    func testVarreduraDosParametros() {
        let consultas = ConsultasDeReferencia.todas
        let ids = BibliotecaDeReferencia.ids
        var atual = ParametrosBM25F.padrao
        var avaliacaoAtual = MetricasDeBusca.avaliar(consultas, motor: motor, ids: ids, parametros: atual)
        print("[varredura] início · \(resumo(avaliacaoAtual)) · \(descricao(atual))")

        for volta in 1...2 {
            var trocou = false
            for passo in Self.passos {
                var melhor = (parametros: atual, avaliacao: avaliacaoAtual, valor: Double?.none)
                for valor in passo.valores {
                    let candidato = passo.aplicar(atual, valor)
                    let avaliacao = MetricasDeBusca.avaliar(consultas, motor: motor, ids: ids, parametros: candidato)
                    print("[varredura] volta \(volta) · \(passo.nome) = \(valor) · \(resumo(avaliacao))"
                        + " · mudou: \(mudancas(de: avaliacaoAtual, para: avaliacao))")
                    if Self.melhor(avaliacao, que: melhor.avaliacao) {
                        melhor = (candidato, avaliacao, valor)
                    }
                }
                if let valor = melhor.valor {
                    print("[varredura] volta \(volta) · ESCOLHIDO \(passo.nome) = \(valor) · \(resumo(melhor.avaliacao))")
                    atual = melhor.parametros
                    avaliacaoAtual = melhor.avaliacao
                    trocou = true
                }
            }
            if !trocou { break }
        }
        print("[varredura] fim · \(resumo(avaliacaoAtual)) · \(descricao(atual))")
    }

    private static func melhor(_ a: AvaliacaoDaBusca, que b: AvaliacaoDaBusca) -> Bool {
        let tolerancia = 1e-9
        // O `b` do sumário também escolhe o item mostrado (`notaDoItem`): subir o MRR mostrando o item
        // errado não é ganho.
        if (a.itemCerto ?? 0) < (b.itemCerto ?? 0) - tolerancia { return false }
        if a.mrr > b.mrr + tolerancia { return true }
        return abs(a.mrr - b.mrr) <= tolerancia && a.top1 > b.top1 + tolerancia
    }

    private func resumo(_ avaliacao: AvaliacaoDaBusca) -> String {
        String(
            format: "top1 %.3f · top3 %.3f · MRR %.3f · item %@",
            avaliacao.top1, avaliacao.top3, avaliacao.mrr,
            avaliacao.itemCerto.map { String(format: "%.3f", $0) } ?? "–"
        )
    }

    /// As consultas (de ajuste e sondas) cuja posição ou item mudou, como "#1 2º→1º".
    private func mudancas(de antes: AvaliacaoDaBusca, para depois: AvaliacaoDaBusca) -> String {
        let lista = zip(antes.medicoes, depois.medicoes).enumerated().compactMap { indice, par -> String? in
            let (a, d) = par
            func pos(_ p: Int?) -> String { p.map { "\($0)º" } ?? "–" }
            if a.posicao != d.posicao { return "#\(indice + 1) \(pos(a.posicao))→\(pos(d.posicao))" }
            if a.itemCerto != d.itemCerto { return "#\(indice + 1) item \(d.itemCerto == true ? "✓" : "✗")" }
            return nil
        }
        return lista.isEmpty ? "nada" : lista.joined(separator: ", ")
    }

    private func descricao(_ p: ParametrosBM25F) -> String {
        let campos = CampoBusca.allCases.map {
            "\($0): peso \(p.pesos[$0, default: 0]) b \(p.b[$0, default: 0])"
        }
        return "k1 \(p.k1) · " + campos.joined(separator: " · ")
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

/// Cópias de `ParametrosBM25F` com um valor trocado, para a varredura.
private extension ParametrosBM25F {
    func comPeso(_ campo: CampoBusca, _ valor: Double) -> ParametrosBM25F {
        var novos = pesos
        novos[campo] = valor
        return ParametrosBM25F(k1: k1, pesos: novos, b: b)
    }

    func comB(_ campo: CampoBusca, _ valor: Double) -> ParametrosBM25F {
        var novos = b
        novos[campo] = valor
        return ParametrosBM25F(k1: k1, pesos: pesos, b: novos)
    }

    func comK1(_ valor: Double) -> ParametrosBM25F {
        ParametrosBM25F(k1: valor, pesos: pesos, b: b)
    }
}
