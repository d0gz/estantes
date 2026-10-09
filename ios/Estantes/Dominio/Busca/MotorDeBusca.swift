import Foundation

/// A busca na biblioteca do usuário: junta o índice, o BM25F e os filtros.
///
/// Guarda os livros além do índice porque o filtro precisa de editora, ano, estante e CDDir,
/// que o índice não tem. Quem altera a biblioteca chama `atualizar` ou `remover` em seguida;
/// quem cria, renomeia ou apaga uma categoria chama `atualizar(categorias:)`.
struct MotorDeBusca {
    /// O último termo só é expandido por prefixo a partir deste tamanho: com uma letra, quase todo
    /// o vocabulário entraria.
    static let tamanhoMinimoDoPrefixo = 2

    private var indice = IndiceInvertido()
    private var livros: [UUID: Livro] = [:]
    private var nomesDasCategorias: [UUID: String]

    init(livros: [Livro], categorias: [Categoria]) {
        nomesDasCategorias = categorias.reduce(into: [:]) { $0[$1.id] = $1.nome }
        for livro in livros {
            atualizar(livro)
        }
    }

    // MARK: - Alteração

    /// Inclui ou reindexa o livro.
    mutating func atualizar(_ livro: Livro) {
        livros[livro.id] = livro
        indice.adicionar(livro, nomesDasCategorias: nomesDasCategorias)
    }

    /// Id ausente é ignorado.
    mutating func remover(livroId: UUID) {
        livros[livroId] = nil
        indice.remover(livroId)
    }

    /// Troca a lista de categorias. O índice grava os nomes, então só são reindexados os livros com
    /// uma categoria cujo nome mudou: renomeada, apagada ou nova (um livro pode ter recebido o id
    /// antes de o motor conhecer o nome). Das apagadas, o livro também perde o id, como o
    /// repositório faz (nullify): senão o filtro por categoria ainda acharia o id antigo.
    /// Ids que o motor nunca conheceu (nem antes nem agora) ficam no livro: o repositório não os produz.
    mutating func atualizar(categorias: [Categoria]) {
        let antigos = nomesDasCategorias
        let novos: [UUID: String] = categorias.reduce(into: [:]) { $0[$1.id] = $1.nome }
        let afetadas = Set(antigos.keys).union(novos.keys).filter { antigos[$0] != novos[$0] }
        let apagadas = Set(antigos.keys).subtracting(novos.keys)
        nomesDasCategorias = novos

        guard !afetadas.isEmpty else { return }
        for var livro in livros.values where !livro.categoriaIds.isDisjoint(with: afetadas) {
            livro.categoriaIds.subtract(apagadas)
            atualizar(livro)
        }
    }

    // MARK: - Busca

    /// Os livros que contêm **todos** os termos da consulta (E) e passam no filtro, do mais
    /// relevante ao menos relevante. O último termo vale como prefixo ("prevent" acha "preventiva"),
    /// porque o usuário ainda pode estar digitando. Se ele repete um termo anterior ("prev prev"),
    /// o usuário já passou dele: vale como termo exato.
    ///
    /// Consulta vazia (ou só de palavras vazias): sem filtro, nada; com filtro, todos os livros
    /// que passam nele, em ordem de título.
    func buscar(
        _ texto: String,
        filtro: FiltroBusca = FiltroBusca(),
        parametros: ParametrosBM25F = .padrao
    ) -> [ResultadoBusca] {
        let filtroPreparado = filtro.preparado()
        let termos = Tokenizador.termos(texto)

        guard let ultimo = termos.last else {
            guard !filtroPreparado.estaVazio else { return [] }
            return MotorDeBusca.ordenar(
                livros.values
                    .filter(filtroPreparado.aceita)
                    .map { ResultadoBusca(livro: $0, itemDoSumario: nil, nota: 0) }
            )
        }

        // Soma em ordem fixa (último termo, depois os fixos em ordem alfabética): ver a nota sobre
        // determinismo em `BM25F.notas`.
        // Se o último repete um termo anterior ("penal penal"), ele já está completo: não expande
        // e conta uma vez só, como os repetidos no BM25F.
        var anteriores = Set(termos.dropLast())
        let repetido = anteriores.remove(ultimo) != nil
        let fixos = anteriores.sorted()
        let expansoes = !repetido && ultimo.count >= MotorDeBusca.tamanhoMinimoDoPrefixo
            ? indice.termos(comPrefixo: ultimo)
            : [ultimo]
        var notas = notasDoUltimo(expansoes, parametros: parametros)
        let conjuntoDeExpansoes = Set(expansoes)
        for termo in fixos {
            let notasDoTermo = BM25F.notas(termos: [termo], indice: indice, parametros: parametros)
            // E: só continua quem também tem este termo. O `for` percorre uma cópia de `notas`
            // (dicionário é tipo-valor), então alterar `notas` dentro dele é seguro.
            for (id, nota) in notas {
                notas[id] = notasDoTermo[id].map { nota + $0 }
            }
        }

        // O filtro vem depois do BM25F: aplicado antes, mudaria o IDF e a nota de quem continua.
        return MotorDeBusca.ordenar(
            notas.compactMap { id, nota in
                guard let livro = livros[id], filtroPreparado.aceita(livro) else { return nil }
                let item = melhorItem(de: livro, fixos: fixos, expansoes: conjuntoDeExpansoes, parametros: parametros)
                return ResultadoBusca(livro: livro, itemDoSumario: item, nota: nota)
            }
        )
    }

    /// Nota de cada livro para o último termo: a maior entre as expansões do prefixo, e não a soma,
    /// para que um prefixo com muitas expansões não infle a nota (mesma ideia da saturação).
    /// Como cada expansão traz o próprio IDF, a que costuma vencer é a mais rara na biblioteca.
    private func notasDoUltimo(_ expansoes: [String], parametros: ParametrosBM25F) -> [UUID: Double] {
        var melhores: [UUID: Double] = [:]
        for termo in expansoes {
            for (id, nota) in BM25F.notas(termos: [termo], indice: indice, parametros: parametros) {
                melhores[id] = max(melhores[id] ?? nota, nota)
            }
        }
        return melhores
    }

    /// O item do sumário mostrado no resultado: o de maior nota BM25, com a mesma regra do livro
    /// (termos fixos somados, a maior entre as expansões do último). Calculado só para os livros que
    /// sobraram depois do filtro. No empate, o que vem antes no sumário; `nil` se nenhum item tem
    /// os termos (o livro casou pelo título, autor...).
    private func melhorItem(
        de livro: Livro,
        fixos: [String],
        expansoes: Set<String>,
        parametros: ParametrosBM25F
    ) -> ItemSumario? {
        var melhor: (id: UUID, nota: Double)?
        for item in indice.itensSumario(doLivro: livro.id) {
            // Só as expansões que o item tem: um prefixo curto pode ter centenas, e um item tem
            // poucos termos. Percorrer os termos do item custa O(tamanho do item), não O(expansões).
            let notaDoUltimo = item.frequencias.keys
                .filter(expansoes.contains)
                .map { BM25F.notaDoItem(item, termos: [$0], indice: indice, parametros: parametros) }
                .max() ?? 0
            let nota = fixos.reduce(notaDoUltimo) { soma, termo in
                soma + BM25F.notaDoItem(item, termos: [termo], indice: indice, parametros: parametros)
            }
            // `>` e não `>=`: no empate fica o primeiro. Partir de 0 faz item sem os termos
            // (nota 0) nunca vencer; se nenhum vence, o resultado é `nil`.
            if nota > (melhor?.nota ?? 0) {
                melhor = (item.id, nota)
            }
        }
        guard let id = melhor?.id else { return nil }
        return livro.itensSumario.first { $0.id == id }
    }

    /// Nota maior primeiro; no empate, título (sem acento nem maiúsculas) e, por fim, o id,
    /// para que a ordem seja a mesma em toda execução. O título normalizado é calculado uma vez
    /// por resultado, e não a cada comparação (a ordenação faz O(n log n) comparações).
    private static func ordenar(_ resultados: [ResultadoBusca]) -> [ResultadoBusca] {
        resultados
            .map { (resultado: $0, titulo: Normalizacao.chave($0.livro.titulo), id: $0.livro.id.uuidString) }
            .sorted { a, b in
                if a.resultado.nota != b.resultado.nota { return a.resultado.nota > b.resultado.nota }
                if a.titulo != b.titulo { return a.titulo < b.titulo }
                return a.id < b.id
            }
            .map { $0.resultado }
    }
}
