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

    /// Quantos erros a correção aceita num termo desconhecido: nenhum em termos curtos (com 4 letras,
    /// quase toda palavra está a 1 erro de outra) ou com dígitos ("1779" não pode virar "1770"); 1 até
    /// 8 letras; 2 a partir de 9.
    static func errosAceitos(em termo: String) -> Int? {
        guard termo.allSatisfy(\.isLetter) else { return nil }
        switch termo.count {
        case ..<5: return nil
        case ...8: return 1
        default: return 2
        }
    }

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
    /// Uma palavra que não existe na biblioteca (o E daria nenhum resultado) é trocada pelo termo mais
    /// próximo, se houver um perto o bastante (`errosAceitos`); a troca vem em `correcoes`. Palavra
    /// que existe nunca é trocada. `corrigir: false` desliga (a tela oferece "buscar exatamente").
    ///
    /// Se nenhum livro tem todos os termos (já com o filtro) e a consulta tem dois ou mais, vale o OU
    /// de reserva (`modo == .parteDosTermos`): os livros com parte dos termos, cada um com as palavras
    /// que faltaram. Com um termo só, não há o que relaxar: a lista fica vazia.
    ///
    /// Consulta vazia (ou só de palavras vazias): sem filtro, nada; com filtro, todos os livros
    /// que passam nele, em ordem de título.
    func buscar(
        _ texto: String,
        filtro: FiltroBusca = FiltroBusca(),
        parametros: ParametrosBM25F = .padrao,
        corrigir: Bool = true
    ) -> RespostaBusca {
        let filtroPreparado = filtro.preparado()
        // O prefixo usa a palavra como foi digitada ("cautelare"); o resto usa o termo no singular.
        let palavras = Tokenizador.palavras(texto)
        var termos = palavras.map(Singular.forma)

        guard let ultimaPalavra = palavras.last else {
            guard !filtroPreparado.estaVazio else {
                return RespostaBusca(resultados: [], modo: .todosOsTermos, correcoes: [])
            }
            let todos = livros.values
                .filter(filtroPreparado.aceita)
                .map { ResultadoBusca(livro: $0, itensDoSumario: [], nota: 0) }
            return RespostaBusca(resultados: MotorDeBusca.ordenar(todos), modo: .todosOsTermos, correcoes: [])
        }

        var correcoes: [Correcao] = []
        if corrigir {
            for i in termos.indices.dropLast() {
                if let usado = correcao(de: termos[i]) {
                    correcoes.append(Correcao(digitado: palavras[i], usado: usado))
                    termos[i] = usado
                }
            }
        }
        // Para o OU dizer o que faltou com a palavra que o usuário escreveu, e não com o termo.
        var palavraDoTermo: [String: String] = [:]
        for (termo, palavra) in zip(termos, palavras) where palavraDoTermo[termo] == nil {
            palavraDoTermo[termo] = palavra
        }
        let ultimo = termos[termos.count - 1]

        // Soma em ordem fixa (último termo, depois os fixos em ordem alfabética): ver a nota sobre
        // determinismo em `BM25F.notas`.
        // Se o último repete um termo anterior ("penal penal"), ele já está completo: não expande
        // e conta uma vez só, como os repetidos no BM25F.
        var anteriores = Set(termos.dropLast())
        let repetido = anteriores.remove(ultimo) != nil
        var expansoes = !repetido && ultimaPalavra.count >= MotorDeBusca.tamanhoMinimoDoPrefixo
            ? indice.termos(comPrefixo: ultimaPalavra)
            : [ultimo]
        // O último só é corrigido se nem o prefixo achou nada: "lassal" ainda está sendo digitado.
        let ultimoExiste = expansoes.contains { indice.quantidadeDeLivros(contendo: $0) > 0 }
        if corrigir, !ultimoExiste, let usado = correcao(de: ultimo) {
            correcoes.append(Correcao(digitado: ultimaPalavra, usado: usado))
            // Corrigido, pode repetir um anterior ("processo procesos"): conta uma vez só.
            anteriores.remove(usado)
            expansoes = [usado]
        }
        let fixos = anteriores.sorted()
        let notasDoUltimo = notasDoUltimo(expansoes, parametros: parametros)
        let notasDosFixos = fixos.map { BM25F.notas(termos: [$0], indice: indice, parametros: parametros) }
        let conjuntoDeExpansoes = Set(expansoes)

        // O filtro vem depois do BM25F: aplicado antes, mudaria o IDF e a nota de quem continua.
        func resultados(_ notas: [UUID: Double], ausentes: [UUID: [String]]) -> [ResultadoBusca] {
            MotorDeBusca.ordenar(
                notas.compactMap { id, nota in
                    guard let livro = livros[id], filtroPreparado.aceita(livro) else { return nil }
                    let itens = itensQueCasam(de: livro, fixos: fixos, expansoes: conjuntoDeExpansoes)
                    return ResultadoBusca(
                        livro: livro, itensDoSumario: itens, nota: nota, palavrasAusentes: ausentes[id] ?? []
                    )
                }
            )
        }

        var notas = notasDoUltimo
        for notasDoTermo in notasDosFixos {
            // E: só continua quem também tem este termo. O `for` percorre uma cópia de `notas`
            // (dicionário é tipo-valor), então alterar `notas` dentro dele é seguro.
            for (id, nota) in notas {
                notas[id] = notasDoTermo[id].map { nota + $0 }
            }
        }
        let comTodos = resultados(notas, ausentes: [:])
        guard comTodos.isEmpty, !fixos.isEmpty else {
            return RespostaBusca(resultados: comTodos, modo: .todosOsTermos, correcoes: correcoes)
        }

        // OU de reserva: a lista ficaria vazia e há dois ou mais termos. Entra quem tem pelo menos um,
        // com a nota dos que tem (somada na mesma ordem do E) e as palavras que faltaram; a ordenação
        // põe primeiro quem tem mais termos (nível de coordenação).
        let porTermo = [(ultimaPalavra, notasDoUltimo)] + zip(fixos, notasDosFixos).map { termo, notas in
            (palavraDoTermo[termo] ?? termo, notas)
        }
        var notasParciais: [UUID: Double] = [:]
        var ausentes: [UUID: [String]] = [:]
        for id in Set(porTermo.flatMap { $0.1.keys }) {
            for (palavra, notasDoTermo) in porTermo {
                if let nota = notasDoTermo[id] {
                    notasParciais[id, default: 0] += nota
                } else {
                    ausentes[id, default: []].append(palavra)
                }
            }
            // Na ordem em que o usuário escreveu.
            ausentes[id]?.sort { (palavras.firstIndex(of: $0) ?? 0) < (palavras.firstIndex(of: $1) ?? 0) }
        }
        return RespostaBusca(
            resultados: resultados(notasParciais, ausentes: ausentes), modo: .parteDosTermos, correcoes: correcoes
        )
    }

    /// O termo do vocabulário que substitui `termo`, se ele não existe na biblioteca e há um perto o
    /// bastante. Termo que existe nunca é corrigido: "pena" não vira "penal".
    private func correcao(de termo: String) -> String? {
        guard indice.quantidadeDeLivros(contendo: termo) == 0,
              let limite = MotorDeBusca.errosAceitos(em: termo) else { return nil }
        return indice.termoMaisProximo(de: termo, limite: limite)
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

    /// Os itens do sumário mostrados no resultado, na ordem do sumário e sem limite: mostrar só o de
    /// melhor nota escondia os outros (teste no iPhone, 03/11). Ficam os itens com o maior número de
    /// palavras da consulta que algum item do livro alcança. "Todas as palavras" falhava quando parte da
    /// consulta está no título ("tratado direito privado dissidios coletivos"), e "qualquer palavra"
    /// listaria todo item com "direito". As palavras do título não contam (o "direito" do título fazia um
    /// cabeçalho genérico esconder o "§ 5.153 Dissídios coletivos"), a não ser que todas estejam nele. Vale
    /// igual no E e no OU de reserva. Calculado só para os livros que sobraram depois do filtro. Vazio se
    /// nenhum item tem os termos (o livro casou pelo título, autor...).
    private func itensQueCasam(de livro: Livro, fixos: [String], expansoes: Set<String>) -> [ItemSumario] {
        let (fixosContados, contaOUltimo) = palavrasQueContam(livro: livro, fixos: fixos, expansoes: expansoes)
        let contagens = indice.itensSumario(doLivro: livro.id).map { item -> (id: UUID, palavras: Int) in
            // Só as expansões que o item tem: um prefixo curto pode ter centenas, e um item tem
            // poucos termos. Percorrer os termos do item custa O(tamanho do item), não O(expansões).
            let temOUltimo = contaOUltimo && item.frequencias.keys.contains(where: expansoes.contains)
            let fixosNoItem = fixosContados.filter { item.frequencias[$0] != nil }.count
            return (item.id, fixosNoItem + (temOUltimo ? 1 : 0))
        }
        guard let maximo = contagens.map(\.palavras).max(), maximo > 0 else { return [] }
        let ids = Set(contagens.filter { $0.palavras == maximo }.map(\.id))
        return livro.itensSumario.filter { ids.contains($0.id) }
    }

    /// As palavras da consulta que contam para os itens do livro: todas menos as do título; se todas estão no
    /// título, todas contam. Só o título: o subtítulo traz a matéria ("Contrato coletivo do trabalho") e as
    /// pontas dos artigos, que são o assunto procurado.
    private func palavrasQueContam(
        livro: Livro,
        fixos: [String],
        expansoes: Set<String>
    ) -> (fixos: [String], contaOUltimo: Bool) {
        let doTitulo = indice.termosDoTitulo(doLivro: livro.id)
        let fixosForaDoTitulo = fixos.filter { !doTitulo.contains($0) }
        // Percorre o título (poucos termos), e não as expansões (um prefixo curto tem centenas).
        let ultimoNoTitulo = doTitulo.contains(where: expansoes.contains)
        if fixosForaDoTitulo.isEmpty && ultimoNoTitulo {
            return (fixos, true)
        }
        return (fixosForaDoTitulo, !ultimoNoTitulo)
    }

    /// Menos palavras ausentes primeiro (só difere no OU: quem tem 2 de 3 termos vem antes de quem tem
    /// 1 de 3, qualquer que seja a nota); depois nota maior; no empate, título (sem acento nem
    /// maiúsculas) e, por fim, o id, para que a ordem seja a mesma em toda execução. O título
    /// normalizado é calculado uma vez por resultado, e não a cada comparação (a ordenação faz
    /// O(n log n) comparações).
    private static func ordenar(_ resultados: [ResultadoBusca]) -> [ResultadoBusca] {
        resultados
            .map { (resultado: $0, titulo: Normalizacao.chave($0.livro.titulo), id: $0.livro.id.uuidString) }
            .sorted { a, b in
                let ausentesA = a.resultado.palavrasAusentes.count, ausentesB = b.resultado.palavrasAusentes.count
                if ausentesA != ausentesB { return ausentesA < ausentesB }
                if a.resultado.nota != b.resultado.nota { return a.resultado.nota > b.resultado.nota }
                if a.titulo != b.titulo { return a.titulo < b.titulo }
                return a.id < b.id
            }
            .map { $0.resultado }
    }
}
