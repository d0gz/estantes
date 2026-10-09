import Foundation

/// Pesos e parâmetros do BM25F: título pesa mais, autor pesa pouco; o `b` é maior nos campos longos
/// (sumário), onde o tamanho mais distorce a contagem.
struct ParametrosBM25F {
    /// Saturação: quanto maior, mais devagar as repetições do termo deixam de contar.
    let k1: Double
    /// Peso de cada campo na frequência combinada. Campo ausente vale 0.
    let pesos: [CampoBusca: Double]
    /// Força da normalização pelo tamanho, de 0 (desligada) a 1 (total). Campo ausente vale 0.
    let b: [CampoBusca: Double]

    /// Fora desses limites a fórmula divide por zero ou dá nota negativa. As propriedades são `let`
    /// para que ninguém contorne a validação depois de criado.
    init(k1: Double, pesos: [CampoBusca: Double], b: [CampoBusca: Double]) {
        precondition(k1 >= 0, "k1 não pode ser negativo")
        precondition(pesos.values.allSatisfy { $0 >= 0 }, "pesos não podem ser negativos")
        precondition(b.values.allSatisfy { (0...1).contains($0) }, "b fica entre 0 e 1")
        self.k1 = k1
        self.pesos = pesos
        self.b = b
    }

    /// Ajustado com as consultas de referência (tabelas em docs/aprendizado/fase-2.md): só o peso do
    /// sumário mudou, porque um livro com o termo em vários itens do sumário passava à frente do que o
    /// tem no título. No passo 6 da 2.3 foi de 1,0 para 0,5; na 2.3i, para 0,25, depois que o plural
    /// tirou a parte estrutural da "prisao caut" e duas consultas de risco inverso (termo só no sumário
    /// do livro certo) não pioraram. Os demais valores não mudaram nenhuma consulta do conjunto:
    /// continuam os de partida, sem terem sido validados.
    static let padrao = ParametrosBM25F(
        k1: 1.2,
        pesos: [.titulo: 3.0, .subtitulo: 2.0, .categorias: 1.5, .cddirCaminho: 1.5, .sumario: 0.25, .autores: 0.5],
        // No autor, b = 0: o tamanho de um nome não diz nada sobre a relevância.
        b: [.titulo: 0.5, .subtitulo: 0.5, .categorias: 0.3, .cddirCaminho: 0.3, .sumario: 0.75, .autores: 0]
    )
}

/// Ranking BM25F: para cada termo, as frequências dos campos são normalizadas pelo tamanho,
/// multiplicadas pelos pesos e somadas; só então a soma satura (`k1`) e é multiplicada pelo IDF.
/// Saturar uma vez por termo, e não uma vez por campo, impede que um termo presente em vários
/// campos infle a nota: cada termo contribui no máximo com o seu IDF.
enum BM25F {
    /// Raridade do termo: ln(1 + (N − df + 0,5) / (df + 0,5)). O "1 +" (variante do Lucene)
    /// mantém o valor positivo mesmo para um termo presente em todos os livros.
    static func idf(totalDeLivros: Int, livrosComOTermo: Int) -> Double {
        let n = Double(totalDeLivros)
        let df = Double(livrosComOTermo)
        return log(1 + (n - df + 0.5) / (df + 0.5))
    }

    /// Nota de cada livro que contém ao menos um termo da consulta; os demais não aparecem.
    /// Termos repetidos na consulta contam uma vez. Um livro cujo termo só aparece em campos de
    /// peso 0 entra com nota 0: cabe ao motor decidir se o mostra.
    ///
    /// Termos e campos são somados em ordem fixa: `Set` e dicionário mudam de ordem a cada execução,
    /// e somas de `Double` em ordens diferentes podem diferir na última casa e mudar um desempate.
    static func notas(
        termos: [String],
        indice: IndiceInvertido,
        parametros: ParametrosBM25F = .padrao
    ) -> [UUID: Double] {
        var notas: [UUID: Double] = [:]

        for termo in Set(termos).sorted() {
            let ocorrencias = indice.ocorrencias(de: termo)
            guard !ocorrencias.isEmpty else { continue }
            let idfDoTermo = idf(totalDeLivros: indice.totalDeLivros, livrosComOTermo: ocorrencias.count)

            for (livroId, frequencias) in ocorrencias {
                // Só os campos onde o termo aparece: tf > 0 garante tamanho e média > 0.
                var tfPonderado = 0.0
                for campo in CampoBusca.allCases {
                    guard let tf = frequencias[campo] else { continue }
                    let fator = fatorDeTamanho(
                        b: parametros.b[campo, default: 0],
                        tamanho: indice.tamanho(de: campo, noLivro: livroId),
                        media: indice.tamanhoMedio(de: campo)
                    )
                    tfPonderado += parametros.pesos[campo, default: 0] * Double(tf) / fator
                }
                notas[livroId, default: 0] += idfDoTermo * saturar(tfPonderado, k1: parametros.k1)
            }
        }
        return notas
    }

    /// BM25 de um campo só, para escolher o item do sumário mostrado no resultado. Usa o IDF do
    /// livro inteiro, o `k1`, o `b` do sumário e o tamanho médio dos itens da biblioteca.
    static func notaDoItem(
        _ item: ItemSumarioIndexado,
        termos: [String],
        indice: IndiceInvertido,
        parametros: ParametrosBM25F = .padrao
    ) -> Double {
        let fator = fatorDeTamanho(
            b: parametros.b[.sumario, default: 0],
            tamanho: item.tamanho,
            media: indice.tamanhoMedioDosItens
        )
        return Set(termos).sorted().reduce(0) { nota, termo in
            guard let tf = item.frequencias[termo] else { return nota }
            let idfDoTermo = idf(
                totalDeLivros: indice.totalDeLivros,
                livrosComOTermo: indice.quantidadeDeLivros(contendo: termo)
            )
            return nota + idfDoTermo * saturar(Double(tf) / fator, k1: parametros.k1)
        }
    }

    /// (1 − b) + b · tamanho / média: 1 para um campo do tamanho médio, maior para um mais longo.
    /// Média 0 só acontece quando nenhum livro tem o campo; aí não há tf a normalizar e vale 1.
    private static func fatorDeTamanho(b: Double, tamanho: Int, media: Double) -> Double {
        guard media > 0 else { return 1 }
        return (1 - b) + b * Double(tamanho) / media
    }

    /// tf / (k1 + tf): cresce cada vez menos e nunca passa de 1.
    private static func saturar(_ tf: Double, k1: Double) -> Double {
        guard tf > 0 else { return 0 }
        return tf / (k1 + tf)
    }
}
