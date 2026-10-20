import SwiftUI

/// O que o Inicio mostra com a busca ativa: a linha de chips de filtro, os avisos (correção e OU de
/// reserva) e os livros achados. A busca roda a cada mudança da `chave` (texto, filtros, "exatamente").
struct ResultadosDaBuscaView<Cabecalho: View>: View {
    @ObservedObject var busca: BuscaViewModel
    let miniaturas: CarregadorDeMiniaturas
    /// Empurra a tela "Filtros"; quem monta esta vista (a `BuscaView`) é quem empurra.
    let abrirFiltros: () -> Void
    /// Empurra a tela Categorias (várias de uma vez).
    let abrirCategorias: () -> Void
    /// O campo de busca, que vai no cabeçalho fixo junto com os chips.
    @ViewBuilder let cabecalho: () -> Cabecalho

    var body: some View {
        ScrollView {
            conteudo
                .padding(Espaco.padrao)
        }
        // Campo e chips fixos sobre os resultados, em "vidro" (o elemento flutuante do Estilo 0): os filtros ficam
        // sempre a um toque, e a lista rola por baixo.
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: Espaco.pequeno) {
                cabecalho()
                    .padding(.horizontal, Espaco.padrao)
                barraDeFiltros
            }
            .padding(.vertical, Espaco.pequeno)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) { Divider() }
        }
        .task { await busca.carregarOpcoes() }
        // Mudou a chave: o SwiftUI cancela a busca anterior e começa esta.
        .task(id: busca.chave) { await busca.buscar() }
        // Ao voltar do Detalhe, o livro pode ter sido editado ou apagado (e uma estante, renomeada).
        .aoVoltar {
            await busca.carregarOpcoes()
            await busca.buscar()
        }
    }

    // MARK: Filtros

    /// Uma linha que rola na horizontal: na busca, os resultados importam mais que os filtros.
    private var barraDeFiltros: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Espaco.pequeno) {
                Button(action: abrirFiltros) {
                    let quantidade = busca.quantidadeNaFolha
                    Label(quantidade > 0 ? "Filtros (\(quantidade))" : "Filtros",
                          systemImage: quantidade > 0
                              ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .chipDeFiltro(marcado: quantidade > 0)
                }
                menuDeCategorias
                // Com uma estante só, filtrar por ela não muda nada.
                if busca.estantes.count > 1 {
                    ForEach(busca.estantes) { estante in
                        chip(estante.nome, marcado: busca.filtro.estanteIds.contains(estante.id)) {
                            busca.alternar(estante: estante.id)
                        }
                    }
                }
            }
            .buttonStyle(EstiloPressao())
            .padding(.horizontal, Espaco.padrao)
        }
    }

    /// Empurra a tela Categorias, em que se marcam várias de uma vez: o `Menu` do iOS 16 fecha a cada toque (mantê-lo
    /// aberto é do 16.4, que o Xcode 14.2 não compila). Sem categorias, o chip não aparece.
    @ViewBuilder
    private var menuDeCategorias: some View {
        if !busca.categorias.isEmpty {
            let marcadas = !busca.filtro.categoriaIds.isEmpty
            Button(action: abrirCategorias) {
                Label(busca.rotuloDasCategorias, systemImage: "chevron.down")
                    .labelStyle(RotuloComIconeDepois())
                    .chipDeFiltro(marcado: marcadas)
            }
            .accessibilityAddTraits(marcadas ? .isSelected : [])
        }
    }

    private func chip(_ nome: String, marcado: Bool, alternar: @escaping () -> Void) -> some View {
        Button(action: alternar) {
            Group {
                if marcado {
                    Label(nome, systemImage: "checkmark")
                } else {
                    Text(nome)
                }
            }
            .chipDeFiltro(marcado: marcado)
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
            // Faixa com ícone, sem cartão: um cartão chamaria mais atenção que o próprio resultado.
            Label {
                VStack(alignment: .leading, spacing: Espaco.minimo) {
                    Text("Mostrando resultados para ")
                        + Text(resposta.correcoes.map(\.usado).joined(separator: ", ")).bold()
                        + Text(".")
                    Button("Buscar exatamente \"\(resposta.correcoes.map(\.digitado).joined(separator: ", "))\"") {
                        busca.buscarExatamente()
                    }
                    .foregroundColor(Cor.destaque)
                }
            } icon: {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(Cor.textoSecundario)
            }
            .font(.subheadline)
        }
        if resposta.modo == .parteDosTermos {
            Label {
                Text("Nenhum livro tem todas as palavras. Mostrando os que têm parte delas.")
            } icon: {
                Image(systemName: "text.magnifyingglass")
            }
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

    /// Os chips do livro, o item do sumário (o motivo da busca, em destaque) e, mais discreto, onde o livro está;
    /// no OU, o que faltou.
    @ViewBuilder
    private func rodape(_ resultado: ResultadoBusca) -> some View {
        let categorias = busca.categorias(de: resultado.livro)
        VStack(alignment: .leading, spacing: Espaco.minimo) {
            // Só mostram: o toque abre o Detalhe, como o resto da linha. Sem o fantasma "+ Categoria":
            // na busca o assunto é achar o livro, não catalogá-lo.
            if !categorias.isEmpty {
                FluxoDeChips {
                    ForEach(categorias) { ChipDeCategoria($0) }
                }
                .padding(.bottom, Espaco.pequeno)
            }
            if let item = LinhaDoResultado.item(resultado.itemDoSumario) {
                Label(item, systemImage: "list.bullet.indent")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            if let lugar = LinhaDoResultado.lugar(
                estante: busca.nomeDaEstante(resultado.livro.estanteId), prateleira: resultado.livro.prateleira
            ) {
                Label(lugar, systemImage: "books.vertical")
                    .font(.subheadline)
                    .foregroundColor(Cor.textoSecundario)
            }
            if let ausentes = LinhaDoResultado.ausentes(resultado.palavrasAusentes) {
                Text(ausentes)
                    .font(.caption)
                    .foregroundColor(Cor.textoSecundario)
            }
        }
        .symbolRenderingMode(.hierarchical)
    }
}

private extension View {
    /// Chip de filtro (E1): cápsula cinza do sistema quando desmarcado; na `superficie` quando marcado, com texto em
    /// `.primary` (o destaque sobre a `superficie` só como forma, regra do Estilo 0). A marca vem do ✓ ou do `.fill`.
    func chipDeFiltro(marcado: Bool) -> some View {
        font(.subheadline)
            .foregroundColor(.primary)
            .padding(.horizontal, Espaco.medio)
            .padding(.vertical, Espaco.pequeno)
            .background(Capsule().fill(marcado ? Cor.superficie : Color(uiColor: .tertiarySystemFill)))
            .contentShape(Capsule())
    }
}

/// Texto antes e ícone depois ("Constitucional ▾"), como nos menus suspensos.
private struct RotuloComIconeDepois: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Espaco.minimo) {
            configuration.title
            configuration.icon
                .imageScale(.small)
        }
    }
}
