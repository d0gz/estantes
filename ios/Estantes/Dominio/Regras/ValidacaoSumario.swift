import Foundation

/// Regra única do formato do sumário. Vale para toda origem: escrita à mão (2.6), foto + parser
/// (Fase 3), Gemini e LexML (Fase 4).
///
/// `validar` foi escrita pelo Ricardo na 2.1; na 2.3b (páginas em texto) a comparação de páginas
/// passou a respeitar a sequência (romanos do prefácio × arábicos do corpo).
enum ValidacaoSumario {
    /// Cada problema aponta o índice do item no array (0 = primeiro).
    enum Problema: Equatable {
        /// Erro: nível menor que 1.
        case nivelInvalido(indice: Int)
        /// Erro: o nível subiu mais de 1 em relação ao item anterior (o primeiro item precisa ser nível 1).
        case saltoDeNivel(indice: Int)
        /// Erro: título vazio ou só com espaços.
        case tituloVazio(indice: Int)
        /// Aviso: página menor que a do último item anterior com página, sendo os dois da mesma sequência
        /// (romana ou arábica). "XII" → "1" é troca de sequência, não regressão.
        case paginaMenorQueAnterior(indice: Int)
    }

    struct Resultado: Equatable {
        var erros: [Problema]
        var avisos: [Problema]

        /// Avisos não impedem salvar; erros impedem.
        var valido: Bool { erros.isEmpty }
    }

    static func validar(_ itens: [ItemSumario]) -> Resultado {
        var erros: [Problema] = []
        var avisos: [Problema] = []
        var itemAnteriorNivel = 0
        // A última página interpretável; texto como "s/n" é pulado, como um item sem página.
        var pagItemAnterior: NumeroDePagina? = nil
        for(index, element) in itens.enumerated()
        {
    
            if element.nivel < 1
            {
                erros.append(.nivelInvalido(indice: index))
            }
            else if (element.nivel - itemAnteriorNivel) > 1
            {
                erros.append(.saltoDeNivel(indice: index))
            }
            
            if element.titulo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                erros.append(.tituloVazio(indice: index))
            }
            
            if let pagAtual = element.numeroDaPagina
            {
                if let pagAnterior = pagItemAnterior,
                    paginaVoltou(de: pagAnterior, para: pagAtual)
                {
                    avisos.append(.paginaMenorQueAnterior(indice: index))
                }

                pagItemAnterior = pagAtual
            }
            itemAnteriorNivel = element.nivel
        }
        return Resultado(erros: erros, avisos: avisos)
    }

    /// Só compara dentro da mesma sequência; ao trocar de sequência, a comparação recomeça do item atual.
    private static func paginaVoltou(de anterior: NumeroDePagina, para atual: NumeroDePagina) -> Bool {
        switch (anterior, atual) {
        case let (.arabico(a), .arabico(b)), let (.romano(a), .romano(b)):
            return b < a
        default:
            return false
        }
    }
}
