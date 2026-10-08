import Foundation

/// Regra única do formato do sumário. Vale para toda origem: escrita à mão (2.6), foto + parser
/// (Fase 3), Gemini e LexML (Fase 4).
///
/// [eu escrevo] — Ricardo implementa `validar`. Os tipos abaixo já estão prontos.
enum ValidacaoSumario {
    /// Cada problema aponta o índice do item no array (0 = primeiro).
    enum Problema: Equatable {
        /// Erro: nível menor que 1.
        case nivelInvalido(indice: Int)
        /// Erro: o nível subiu mais de 1 em relação ao item anterior (o primeiro item precisa ser nível 1).
        case saltoDeNivel(indice: Int)
        /// Erro: título vazio ou só com espaços.
        case tituloVazio(indice: Int)
        /// Aviso: página menor que a do último item anterior que tinha página.
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
        var pagItemAnterior: Int? = nil
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
            
            if let pagAtual = element.pagina
            {
                if let pagAnterior = pagItemAnterior,
                    pagAtual < pagAnterior
                {
                    avisos.append(.paginaMenorQueAnterior(indice: index))
                }
                
            pagItemAnterior = pagAtual
            }
            itemAnteriorNivel = element.nivel
        }
        return Resultado(erros: erros, avisos: avisos)
    }
}
