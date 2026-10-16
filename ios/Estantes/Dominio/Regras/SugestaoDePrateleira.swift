import Foundation

/// Etiquetas de prateleira a sugerir enquanto o usuário digita, para reaproveitar as que já existem na estante
/// em vez de criar outra grafia da mesma ("Caixa azul" × "caixa azul").
///
/// - Etiquetas que só diferem em maiúsculas, acentos ou espaços viram uma sugestão só (comparadas pela
///   `Normalizacao.chave`, como no `AgrupamentoPorPrateleira`); fica a primeira grafia em ordem natural, com os espaços arrumados.
/// - Sem texto: todas, em ordem natural ("2ª de cima" antes de "10ª de cima").
/// - Com texto: primeiro as que começam por ele, depois as que só o contêm; cada grupo em ordem natural.
/// - A etiqueta igual ao que já está digitado não aparece: não há o que completar.
enum SugestaoDePrateleira {
    static func sugerir(para texto: String, entre etiquetas: [String], limite: Int = 5) -> [String] {
        let digitado = Normalizacao.chave(texto)

        var comecam: [String] = []
        var contem: [String] = []
        for etiqueta in semGrafiasRepetidas(etiquetas) {
            let chave = Normalizacao.chave(etiqueta)
            if chave == digitado { continue }
            if chave.hasPrefix(digitado) {
                comecam.append(etiqueta)
            } else if chave.contains(digitado) {
                contem.append(etiqueta)
            }
        }
        return Array((comecam + contem).prefix(limite))
    }

    /// Uma grafia por chave (sem espaços nas pontas nem repetidos no meio), em ordem natural;
    /// etiquetas só de espaços ficam de fora.
    private static func semGrafiasRepetidas(_ etiquetas: [String]) -> [String] {
        let ordenadas = etiquetas
            .map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .sorted { a, b in
                // Se a ordem natural empatar duas grafias, o `sorted` (que não é estável) poderia escolher
                // uma ou outra conforme a ordem de chegada; o desempate pelo texto cru fixa a escolha.
                let ordem = a.localizedStandardCompare(b)
                return ordem == .orderedSame ? a < b : ordem == .orderedAscending
            }
        var vistas = Set<String>()
        return ordenadas.filter { vistas.insert(Normalizacao.chave($0)).inserted }
    }
}
