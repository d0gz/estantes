import Foundation

/// A busca na biblioteca do usuário: junta o índice, o BM25F e os filtros.
///
/// Guarda os livros além do índice porque o filtro precisa de editora, ano, estante e CDDir,
/// que o índice não tem. Quem altera a biblioteca chama `atualizar` ou `remover` em seguida.
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
                    .map { ResultadoBusca(livro: $0, nota: 0) }
            )
        }

        // Soma em ordem fixa (último termo, depois os fixos em ordem alfabética): ver a nota sobre
        // determinismo em `BM25F.notas`.
        // Se o último repete um termo anterior ("penal penal"), ele já está completo: não expande
        // e conta uma vez só, como os repetidos no BM25F.
        var anteriores = Set(termos.dropLast())
        let repetido = anteriores.remove(ultimo) != nil
        let fixos = anteriores.sorted()
        var notas = notasDoUltimo(ultimo, expandir: !repetido, parametros: parametros)
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
                return ResultadoBusca(livro: livro, nota: nota)
            }
        )
    }

    /// Nota de cada livro para o último termo: a maior entre as expansões do prefixo, e não a soma,
    /// para que um prefixo com muitas expansões não infle a nota (mesma ideia da saturação).
    /// Como cada expansão traz o próprio IDF, a que costuma vencer é a mais rara na biblioteca.
    private func notasDoUltimo(_ ultimo: String, expandir: Bool, parametros: ParametrosBM25F) -> [UUID: Double] {
        let expansoes = expandir && ultimo.count >= MotorDeBusca.tamanhoMinimoDoPrefixo
            ? indice.termos(comPrefixo: ultimo)
            : [ultimo]
        var melhores: [UUID: Double] = [:]
        for termo in expansoes {
            for (id, nota) in BM25F.notas(termos: [termo], indice: indice, parametros: parametros) {
                melhores[id] = max(melhores[id] ?? nota, nota)
            }
        }
        return melhores
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
