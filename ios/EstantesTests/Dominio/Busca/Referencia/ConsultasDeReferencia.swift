import Foundation

/// As consultas de referência, escritas **antes** de ver o ranking, como um usuário digitaria.
/// Consulta nova pode entrar; uma existente nunca é reescrita para passar.
/// O número no comentário é o que aparece no relatório (`[referencia] #N`).
enum ConsultasDeReferencia {
    static let todas: [ConsultaDeReferencia] = ajuste + sondas + ajusteDasSondas

    static let ajuste: [ConsultaDeReferencia] = [
        // 1–2 título: "processo penal" também está no título do Rosa e no sumário de outros.
        ConsultaDeReferencia("processo penal", esperado: "badaro", caso: .titulo),
        ConsultaDeReferencia("a essencia da constituicao", esperado: "lassale", caso: .titulo),
        // 3–4 autor: Carvalho Neto e "dos Santos" (Fernandes) atrapalham.
        ConsultaDeReferencia("carvalho santos", esperado: "carvalho-santos-v24", caso: .autor),
        ConsultaDeReferencia("capez prisao", esperado: "capez", caso: .autor),
        // 5–6 categoria: o Lassale tem a categoria e "poder" no sumário; Paula, no título.
        ConsultaDeReferencia("historia constituicao", esperado: "borges", caso: .categoria),
        ConsultaDeReferencia("constitucional poder", esperado: "paula", caso: .categoria),
        // 7–8 CDDir
        ConsultaDeReferencia("hereditario", esperado: "mendes", caso: .cddir),
        ConsultaDeReferencia("duracao trabalho", esperado: "luca", caso: .cddir),
        // 9–10 sumário
        ConsultaDeReferencia("fideicomisso", esperado: "carvalho-santos-v24", item: "Art. 1.733", caso: .sumario),
        ConsultaDeReferencia(
            "flagrante delito", esperado: "sarlet",
            item: "Inviolabilidade de domicílio em caso de flagrante delito.", caso: .sumario
        ),
        // 11 prefixo: concorre com Maluf ("Terrorismo e prisão cautelar") e Capez ("cautelares").
        ConsultaDeReferencia("prisao caut", esperado: "fernandes", caso: .prefixo),
        // 12 ortografia antiga: "sôbre" no título.
        ConsultaDeReferencia("direitos sobre coisa alheia", esperado: "espinola", caso: .ortografiaAntiga),
        // 13–14 âncoras
        ConsultaDeReferencia("art 1710", esperado: "carvalho-santos-v24", item: "Art. 1.710", caso: .ancora),
        ConsultaDeReferencia("§ 5.108", esperado: "tratado-t48", item: "§ 5.108", caso: .ancora),
        // 15–16 parte e subtítulo
        ConsultaDeReferencia("tratado parte geral", esperado: "tratado-t1", caso: .parte),
        ConsultaDeReferencia("contrato coletivo trabalho", esperado: "tratado-t48", caso: .parte),
        // 17–18 hífen
        ConsultaDeReferencia("co-herdeiros", esperado: "carvalho-santos-v24", caso: .hifen),
        ConsultaDeReferencia("coherdeiros", esperado: "carvalho-santos-v24", caso: .hifen),
        // 19 tomos com o mesmo título: só o T48 tem "dissídios".
        ConsultaDeReferencia(
            "tratado direito privado dissidios coletivos", esperado: "tratado-t48",
            item: "§ 5.153", caso: .tomo
        )
    ]

    /// Casos que nenhum peso conserta: ficam fora das médias e alimentam decisões sobre o motor.
    /// Quando uma mudança no motor resolve uma, ela vira ajuste no mesmo lugar (`tipo` muda; o texto
    /// e o esperado não), para não mudar a numeração do relatório.
    static let sondas: [ConsultaDeReferencia] = [
        // 20 "1779" não está em nenhum item. Era sonda: virou ajuste na 2.3i, com `artigosInicio/Fim` no índice.
        ConsultaDeReferencia("arts 1710 1779", esperado: "carvalho-santos-v24", caso: .ancora),
        // 21 Era sonda: virou ajuste na 2.3i, com `volume`/`volumeRotulo` no índice.
        ConsultaDeReferencia("tratado 48", esperado: "tratado-t48", caso: .tomo),
        // 22 os dois tomos empatam; o desempate é pelo título e depois pelo UUID.
        ConsultaDeReferencia("tratado direito privado", esperado: "tratado-t1", caso: .tomo, tipo: .sonda),
        // 23 plural, sem stemming.
        ConsultaDeReferencia("prisoes cautelares", esperado: "fernandes", caso: .prefixo, tipo: .sonda),
        // 24 erro de digitação, com E entre os termos.
        ConsultaDeReferencia("procesos penal", esperado: "badaro", caso: .titulo, tipo: .sonda),
        // 25 grafia da capa ("Lassalle") × ficha CIP ("Lassale").
        ConsultaDeReferencia("lassalle", esperado: "lassale", caso: .autor, tipo: .sonda)
    ]

    /// Consultas de ajuste escritas na 2.3i, depois das sondas, para medir o risco de cada mudança no
    /// motor. Ficam no fim para não mudar a numeração das anteriores no relatório.
    static let ajusteDasSondas: [ConsultaDeReferencia] = [
        // 26 plural ao contrário: a consulta no singular, o título no plural ("Inventários e partilhas").
        ConsultaDeReferencia("inventario partilha", esperado: "mendes", caso: .plural),
        // 27 o rótulo do volume em romanos, como impresso na folha de rosto.
        ConsultaDeReferencia("tomo xlviii", esperado: "tratado-t48", caso: .tomo)
    ]
}
