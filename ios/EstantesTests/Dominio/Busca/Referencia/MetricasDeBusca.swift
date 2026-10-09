import Foundation
@testable import Estantes

/// Uma consulta do conjunto de referência e a resposta que um usuário esperaria.
struct ConsultaDeReferencia {
    enum Caso: String {
        case titulo, autor, categoria, cddir, sumario, prefixo, ortografiaAntiga, ancora, parte, hifen, tomo, plural
    }

    /// `ajuste` conta nas métricas que guiam os pesos; `sonda` é um caso que nenhum peso conserta
    /// (plural, termo fora do índice) e só aparece no relatório, para decisões sobre o motor.
    enum Tipo {
        case ajuste, sonda
    }

    let texto: String
    /// Chave legível da ficha esperada ("tratado-t48"), resolvida para o UUID por quem avalia.
    let esperado: String
    /// Numeração ou título do item do sumário que o resultado deve mostrar ("Art. 1.710");
    /// basta casar com um dos dois.
    let itemEsperado: String?
    let caso: Caso
    let tipo: Tipo

    init(_ texto: String, esperado: String, item: String? = nil, caso: Caso, tipo: Tipo = .ajuste) {
        self.texto = texto
        self.esperado = esperado
        self.itemEsperado = item
        self.caso = caso
        self.tipo = tipo
    }
}

/// O que aconteceu com uma consulta: onde o livro esperado ficou e qual item o motor mostrou.
struct MedicaoDeConsulta {
    let consulta: ConsultaDeReferencia
    /// Posição pessimista, a partir de 1; `nil` quando o livro não voltou.
    let posicao: Int?
    let nota: Double?
    /// O item do sumário mostrado no resultado do livro esperado.
    let itemMostrado: ItemSumario?

    /// 1/posição; 0 quando o livro não voltou.
    var rankReciproco: Double {
        posicao.map { 1 / Double($0) } ?? 0
    }

    /// `nil` quando a consulta não espera item ou o livro ficou fora do top 3 (aí o item não é visto).
    var itemCerto: Bool? {
        guard let esperado = consulta.itemEsperado, let posicao = posicao, posicao <= 3 else { return nil }
        return itemMostrado?.numeracao == esperado || itemMostrado?.titulo == esperado
    }
}

/// Métricas agregadas das consultas de ajuste. As sondas ficam em `medicoes`, mas fora das médias.
struct AvaliacaoDaBusca {
    let medicoes: [MedicaoDeConsulta]

    var deAjuste: [MedicaoDeConsulta] { medicoes.filter { $0.consulta.tipo == .ajuste } }

    /// Fração das consultas com o livro esperado em 1º.
    var top1: Double { fracao(deAjuste) { $0.posicao == 1 } }
    /// Fração com o livro esperado entre os 3 primeiros.
    var top3: Double { fracao(deAjuste) { ($0.posicao ?? .max) <= 3 } }
    /// Média de 1/posição: separa 2º de 10º, o que o top 3 não faz.
    var mrr: Double {
        let lista = deAjuste
        guard !lista.isEmpty else { return 0 }
        return lista.map(\.rankReciproco).reduce(0, +) / Double(lista.count)
    }
    /// Fração com o item certo, entre as que esperam item e acharam o livro no top 3; `nil` se nenhuma.
    var itemCerto: Double? {
        let avaliadas = deAjuste.compactMap(\.itemCerto)
        guard !avaliadas.isEmpty else { return nil }
        return Double(avaliadas.filter { $0 }.count) / Double(avaliadas.count)
    }

    private func fracao(_ lista: [MedicaoDeConsulta], _ acertou: (MedicaoDeConsulta) -> Bool) -> Double {
        guard !lista.isEmpty else { return 0 }
        return Double(lista.filter(acertou).count) / Double(lista.count)
    }
}

/// Mede o motor de busca sobre um conjunto de consultas de referência (top 1, top 3, MRR).
/// Fica no alvo de testes: o app nunca calcula essas métricas.
enum MetricasDeBusca {
    /// Notas com diferença menor que isto contam como empate (somas de `Double` em outra ordem
    /// podem diferir na última casa).
    static let toleranciaDeEmpate = 1e-9

    /// Posição do livro, a partir de 1, contando **à frente** todos os outros com nota maior ou igual.
    /// Empate pessimista: o desempate do motor (título, depois UUID) é arbitrário para a relevância,
    /// e um empate que vence por ordem alfabética não pode contar como acerto.
    static func posicao(de livroId: UUID, em resultados: [ResultadoBusca]) -> Int? {
        guard let nota = resultados.first(where: { $0.livro.id == livroId })?.nota else { return nil }
        let naFrente = resultados.filter {
            $0.livro.id != livroId && $0.nota >= nota - toleranciaDeEmpate
        }.count
        return 1 + naFrente
    }

    static func medir(
        _ consulta: ConsultaDeReferencia,
        livroEsperado: UUID,
        resultados: [ResultadoBusca]
    ) -> MedicaoDeConsulta {
        let resultado = resultados.first { $0.livro.id == livroEsperado }
        return MedicaoDeConsulta(
            consulta: consulta,
            posicao: posicao(de: livroEsperado, em: resultados),
            nota: resultado?.nota,
            itemMostrado: resultado?.itemDoSumario
        )
    }

    /// Roda cada consulta no motor. `ids` traduz a chave legível da ficha para o UUID; uma chave
    /// desconhecida é erro do conjunto, não do motor, e para o teste na hora.
    static func avaliar(
        _ consultas: [ConsultaDeReferencia],
        motor: MotorDeBusca,
        ids: [String: UUID],
        parametros: ParametrosBM25F = .padrao
    ) -> AvaliacaoDaBusca {
        AvaliacaoDaBusca(medicoes: consultas.map { consulta in
            guard let id = ids[consulta.esperado] else {
                preconditionFailure("Ficha \"\(consulta.esperado)\" não existe na biblioteca de referência")
            }
            let resultados = motor.buscar(consulta.texto, parametros: parametros).resultados
            return medir(consulta, livroEsperado: id, resultados: resultados)
        })
    }
}
