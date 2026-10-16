import Foundation

/// Regra da cor que a folha de nova categoria já traz escolhida: a menos usada entre as categorias existentes.
/// No empate vale a primeira na ordem da paleta (`CorCategoria.allCases`), não a ordem das existentes nem a
/// alfabética. Assim as cores ficam variadas sem o usuário pensar nelas, e a sugestão é sempre a mesma para a
/// mesma biblioteca.
enum CorSugerida {
    /// - Parameter existentes: as categorias já cadastradas.
    /// - Returns: a cor com menos categorias; no empate, a que vem primeiro na paleta.
    static func sugerir(existentes: [Categoria]) -> CorCategoria {
        var usosPorCor: [CorCategoria: Int] = [:]
        for categoria in existentes {
            usosPorCor[categoria.cor, default: 0] += 1
        }

        // Começa acima de qualquer contagem: a primeira cor do laço sempre substitui, e o `.cinza` inicial nunca
        // é devolvido. O `<` estrito mantém a primeira da paleta no empate.
        var menorUso = Int.max
        var corMenosUsada = CorCategoria.cinza
        for cor in CorCategoria.allCases {
            let uso = usosPorCor[cor, default: 0]
            if uso < menorUso {
                menorUso = uso
                corMenosUsada = cor
            }
        }
        return corMenosUsada
    }
}
