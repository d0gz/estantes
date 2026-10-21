import Foundation

/// Regra da importação "mesclar": junta a biblioteca do aparelho com a de um arquivo e devolve o estado final,
/// que o repositório grava de uma vez.
///
/// O arquivo vence por UUID (é um backup: restaurar é o caso principal); o que só existe no aparelho fica.
/// Um livro vem inteiro do arquivo, então o sumário é substituído em bloco, sem juntar itens.
/// Categorias têm nome único (sem diferenciar maiúsculas e acentos): uma categoria nova do arquivo com o nome
/// de uma que já existe é reaproveitada; se o arquivo renomear uma categoria para o nome de outra do aparelho,
/// as duas se fundem na do arquivo. Nos dois casos, os livros passam a apontar para a que ficou.
enum Mesclagem {
    static func mesclar(aparelho: ConteudoDaBiblioteca, arquivo: ConteudoDaBiblioteca) -> ConteudoDaBiblioteca {
        let (categorias, remapeamento) = mesclarCategorias(aparelho.categorias, arquivo.categorias)
        let livros = unir(aparelho.livros, arquivo.livros).map { livro -> Livro in
            var livro = livro
            livro.categoriaIds = Set(livro.categoriaIds.map { remapeamento[$0] ?? $0 })
            return livro
        }
        return ConteudoDaBiblioteca(
            estantes: unir(aparelho.estantes, arquivo.estantes),
            categorias: categorias,
            livros: livros
        )
    }

    /// Devolve as categorias finais e o remapeamento (id que sumiu → id que ficou) a aplicar nos livros.
    private static func mesclarCategorias(
        _ aparelho: [Categoria], _ arquivo: [Categoria]
    ) -> ([Categoria], [UUID: UUID]) {
        let idsDoAparelho = Set(aparelho.map(\.id))
        let idsDoArquivo = Set(arquivo.map(\.id))
        var resultado = unir(aparelho, arquivo.filter { idsDoAparelho.contains($0.id) })
        var remapeamento: [UUID: UUID] = [:]

        // O arquivo pode ter renomeado uma categoria para o nome de outra que só existe no aparelho:
        // a do aparelho é absorvida pela do arquivo (que venceu pelo UUID).
        for local in resultado where !idsDoArquivo.contains(local.id) {
            let chave = Normalizacao.chave(local.nome)
            if let doArquivo = resultado.first(where: { idsDoArquivo.contains($0.id) && Normalizacao.chave($0.nome) == chave }) {
                remapeamento[local.id] = doArquivo.id
            }
        }
        resultado.removeAll { remapeamento[$0.id] != nil }

        for nova in arquivo where !idsDoAparelho.contains(nova.id) {
            let chave = Normalizacao.chave(nova.nome)
            if let existente = resultado.first(where: { Normalizacao.chave($0.nome) == chave }) {
                remapeamento[nova.id] = existente.id
            } else {
                resultado.append(nova)
            }
        }
        return (resultado, remapeamento)
    }

    /// Ordem fixa: os do aparelho, cada um trocado pelo do arquivo com o mesmo id; depois os que só
    /// existem no arquivo, na ordem dele.
    private static func unir<T: Identifiable>(_ aparelho: [T], _ arquivo: [T]) -> [T] where T.ID == UUID {
        let doArquivo = Dictionary(arquivo.map { ($0.id, $0) }, uniquingKeysWith: { primeiro, _ in primeiro })
        let idsDoAparelho = Set(aparelho.map(\.id))
        return aparelho.map { doArquivo[$0.id] ?? $0 } + arquivo.filter { !idsDoAparelho.contains($0.id) }
    }
}
