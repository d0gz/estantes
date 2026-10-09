import Foundation

/// Distância de edição entre duas palavras: quantas operações de um caractere transformam uma na
/// outra. Serve para corrigir um termo digitado errado ("lassalle" → `lassale`).
///
/// É a de Damerau–Levenshtein restrita (OSA, *optimal string alignment*): inserção, remoção,
/// troca e **transposição de dois vizinhos** ("porcesso" → "processo" custa 1, e não 2), que é o
/// erro de dedo mais comum. "Restrita" porque um trecho transposto não é editado de novo.
enum DistanciaDeEdicao {
    /// A distância, sem limite.
    static func entre(_ a: String, _ b: String) -> Int {
        // Com o limite no máximo possível, o resultado nunca é `nil`.
        entre(a, b, limite: max(a.count, b.count)) ?? max(a.count, b.count)
    }

    /// A distância, ou `nil` se ela passa do limite. O limite permite parar cedo, o que importa
    /// quando a palavra é comparada com o vocabulário inteiro: se os tamanhos já diferem mais que o
    /// limite, nem começa; se uma linha inteira da tabela passa do limite, para.
    static func entre(_ a: String, _ b: String, limite: Int) -> Int? {
        let a = Array(a), b = Array(b)
        guard abs(a.count - b.count) <= limite else { return nil }
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }

        // Programação dinâmica: d[i][j] é a distância entre os i primeiros de `a` e os j primeiros
        // de `b`. Só três linhas ficam na memória: a atual, a anterior e a de antes (transposição).
        var anteriorDaAnterior = [Int](repeating: 0, count: b.count + 1)
        var anterior = Array(0...b.count)
        var atual = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            atual[0] = i
            for j in 1...b.count {
                let custo = a[i - 1] == b[j - 1] ? 0 : 1
                atual[j] = min(
                    anterior[j] + 1,            // remove a[i-1]
                    atual[j - 1] + 1,           // insere b[j-1]
                    anterior[j - 1] + custo     // troca (ou mantém)
                )
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    atual[j] = min(atual[j], anteriorDaAnterior[j - 2] + 1) // transpõe os dois
                }
            }
            // O mínimo de uma linha nunca é menor que o da anterior (toda célula vem de uma célula de
            // cima + algo, ou da esquerda, que começa em `i`; a transposição vem de duas linhas acima + 1,
            // o que não fica abaixo do mínimo da linha de cima). Se a linha passou do limite, o fim passa.
            if atual.min()! > limite { return nil }
            (anteriorDaAnterior, anterior, atual) = (anterior, atual, anteriorDaAnterior)
        }
        let distancia = anterior[b.count]
        return distancia <= limite ? distancia : nil
    }
}
