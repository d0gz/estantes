import SwiftUI

/// O que o Inicio mostra com a busca ativa: a linha de chips de filtro, os avisos (correção e OU de
/// reserva) e os livros achados. A busca roda a cada mudança da `chave` (texto, filtros, "exatamente").
struct ResultadosDaBuscaView: View {
    @ObservedObject var busca: BuscaViewModel
    let miniaturas: CarregadorDeMiniaturas
    @State private var mostrandoFiltros: Bool

    /// - Parameter mostrarFiltros: abre a folha "Filtros" logo de início (só as capturas usam).
    init(busca: BuscaViewModel, miniaturas: CarregadorDeMiniaturas, mostrarFiltros: Bool = false) {
        self.busca = busca
        self.miniaturas = miniaturas
        _mostrandoFiltros = State(initialValue: mostrarFiltros)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espaco.padrao) {
                barraDeFiltros
                conteudo
                    .padding(.horizontal, Espaco.padrao)
            }
            .padding(.vertical, Espaco.padrao)
        }
        .task { await busca.carregarOpcoes() }
        // Mudou a chave: o SwiftUI cancela a busca anterior e começa esta.
        .task(id: busca.chave) { await busca.buscar() }
        // Ao voltar do Detalhe, o livro pode ter sido editado ou apagado (e uma estante, renomeada).
        .aoVoltar {
            await busca.carregarOpcoes()
            await busca.buscar()
        }
        .sheet(isPresented: $mostrandoFiltros) {
            FiltrosDaBuscaView(filtro: $busca.filtro)
        }
    }

    // MARK: Filtros

    /// Uma linha que rola na horizontal: na busca, os resultados importam mais que os filtros.
    private var barraDeFiltros: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Espaco.pequeno) {
                Button {
                    mostrandoFiltros = true
                } label: {
                    let quantidade = busca.quantidadeNaFolha
                    Label(quantidade > 0 ? "Filtros (\(quantidade))" : "Filtros",
                          systemImage: "line.3.horizontal.decrease.circle")
                }
                // Com uma estante só, filtrar por ela não muda nada.
                if busca.estantes.count > 1 {
                    ForEach(busca.estantes) { estante in
                        chip(estante.nome, marcado: busca.filtro.estanteIds.contains(estante.id)) {
                            busca.alternar(estante: estante.id)
                        }
                    }
                }
                ForEach(busca.categorias) { categoria in
                    chip(categoria.nome, marcado: busca.filtro.categoriaIds.contains(categoria.id)) {
                        busca.alternar(categoria: categoria.id)
                    }
                }
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, Espaco.padrao)
        }
    }

    private func chip(_ nome: String, marcado: Bool, alternar: @escaping () -> Void) -> some View {
        Button(action: alternar) {
            if marcado {
                Label(nome, systemImage: "checkmark")
            } else {
                Text(nome)
            }
        }
        .accessibilityAddTraits(marcado ? .isSelected : [])
    }

    // MARK: Conteúdo

    @ViewBuilder
    private var conteudo: some View {
        switch busca.estado {
        case .dica:
            mensagem("Busque por título, autor ou assunto.")
        case .nadaEncontrado:
            if Tokenizador.palavras(busca.texto).isEmpty {
                mensagem("Nenhum livro passa nos filtros.")
            } else {
                mensagem("Nenhum livro encontrado para \"\(busca.texto.trimmingCharacters(in: .whitespaces))\".")
            }
        case .erro(let texto):
            MensagemDeErroView(texto: texto) {
                Task { await busca.buscar() }
            }
        case .resultados(let resposta):
            VStack(alignment: .leading, spacing: Espaco.padrao) {
                avisos(resposta)
                lista(resposta.resultados)
            }
        }
    }

    private func mensagem(_ texto: String) -> some View {
        Text(texto)
            .font(.subheadline)
            .foregroundColor(Cor.textoSecundario)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, Espaco.grande)
    }

    @ViewBuilder
    private func avisos(_ resposta: RespostaBusca) -> some View {
        if !resposta.correcoes.isEmpty {
            VStack(alignment: .leading, spacing: Espaco.minimo) {
                Text("Mostrando resultados para ")
                    + Text(resposta.correcoes.map(\.usado).joined(separator: ", ")).bold()
                    + Text(".")
                Button("Buscar exatamente \"\(resposta.correcoes.map(\.digitado).joined(separator: ", "))\"") {
                    busca.buscarExatamente()
                }
            }
            .font(.subheadline)
        }
        if resposta.modo == .parteDosTermos {
            Text("Nenhum livro tem todas as palavras. Mostrando os que têm parte delas.")
                .font(.subheadline)
                .foregroundColor(Cor.textoSecundario)
        }
    }

    private func lista(_ resultados: [ResultadoBusca]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(resultados.enumerated()), id: \.element.livro.id) { indice, resultado in
                if indice > 0 {
                    DivisorDeLinhaDoLivro()
                }
                NavigationLink(value: RotaDoLivro(livroId: resultado.livro.id)) {
                    LinhaDoLivro(livro: resultado.livro, miniaturas: miniaturas) {
                        rodape(resultado)
                    }
                }
                .buttonStyle(EstiloLinha())
            }
        }
        .cartao()
    }

    /// Onde está o assunto e o livro ("§ 5.108 Conceito, p. 3 · Escritório · 2ª de cima") e, no OU, o que faltou.
    @ViewBuilder
    private func rodape(_ resultado: ResultadoBusca) -> some View {
        let local = LinhaDoResultado.local(
            item: resultado.itemDoSumario,
            estante: busca.nomeDaEstante(resultado.livro.estanteId),
            prateleira: resultado.livro.prateleira
        )
        VStack(alignment: .leading, spacing: 2) {
            if !local.isEmpty {
                Text(local)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            if let ausentes = LinhaDoResultado.ausentes(resultado.palavrasAusentes) {
                Text(ausentes)
                    .font(.caption)
                    .foregroundColor(Cor.textoSecundario)
            }
        }
    }
}
