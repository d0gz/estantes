import SwiftUI

/// Os livros de uma estante: um cartão por prateleira, com a contagem no cabeçalho, e cada livro numa linha com a
/// miniatura (foto livre ou substituta), o título em serifa, o volume e autor · ano. Sem livros, o vazio no padrão
/// do Inicio: ilustração, frase e uma ação só.
struct EstanteView: View {
    @StateObject private var viewModel: EstanteViewModel
    @State private var adicionando: Bool
    private let miniaturas: CarregadorDeMiniaturas
    /// Cria o ViewModel do formulário; vem da montagem para a tela não precisar conhecer `Dependencias`.
    private let formulario: @MainActor (LivroFormularioViewModel.Modo) -> LivroFormularioViewModel
    /// A folha de escolher categorias (e a de criar uma nova, dentro dela); também vêm da montagem.
    private let escolha: @MainActor (UUID) -> EscolhaDeCategoriasViewModel
    private let formularioDeCategoria: @MainActor (CategoriaFormularioViewModel.Modo) -> CategoriaFormularioViewModel
    /// O livro cujas categorias estão sendo escolhidas.
    @State private var escolhendoCategoriasDe: Livro?

    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento
    @Environment(\.dynamicTypeSize) private var tamanhoDoTexto
    /// Largura da miniatura: cresce com o texto grande, para acompanhar o título ao lado.
    @ScaledMetric(relativeTo: .body) private var larguraEscalada: CGFloat = 44

    /// Com teto de 1,5× (66 pt): nos tamanhos de acessibilidade ela passava de um terço da linha e espremia o título.
    private var larguraDaMiniatura: CGFloat {
        min(larguraEscalada, 66)
    }

    init(
        viewModel: @autoclosure @escaping () -> EstanteViewModel,
        miniaturas: CarregadorDeMiniaturas,
        formulario: @escaping @MainActor (LivroFormularioViewModel.Modo) -> LivroFormularioViewModel,
        escolha: @escaping @MainActor (UUID) -> EscolhaDeCategoriasViewModel,
        formularioDeCategoria: @escaping @MainActor (CategoriaFormularioViewModel.Modo) -> CategoriaFormularioViewModel,
        abrirFormulario: Bool = false
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.miniaturas = miniaturas
        self.formulario = formulario
        self.escolha = escolha
        self.formularioDeCategoria = formularioDeCategoria
        _adicionando = State(initialValue: abrirFormulario)
    }

    var body: some View {
        conteudo
            .navigationTitle(viewModel.estante.nome)
            .toolbar {
                // Só com livros na tela: no vazio, a ação única é o botão do estado vazio (como no Inicio).
                if temLivros {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            adicionando = true
                        } label: {
                            Label("Adicionar livro", systemImage: "plus")
                        }
                    }
                }
            }
            // A folha não dispara o `onAppear` da tela de trás ao fechar: a releitura fica no `onDismiss`.
            .sheet(isPresented: $adicionando, onDismiss: { Task { await viewModel.carregar() } }) {
                LivroFormularioView(viewModel: formulario(.novo(estanteId: viewModel.estante.id)))
            }
            .sheet(item: $escolhendoCategoriasDe, onDismiss: { Task { await viewModel.carregar() } }) { livro in
                EscolhaDeCategoriasView(viewModel: escolha(livro.id), formulario: formularioDeCategoria)
            }
            .task { await viewModel.carregar() }
            .aoVoltar { await viewModel.carregar() }
    }

    /// Troca de estado (carregando → lista ou vazio) com a mola `suave`, como no Inicio.
    private var conteudo: some View {
        estadoAtual.animacaoSuave(valor: viewModel.estado)
    }

    private var entrada: AnyTransition {
        .entrada(reduzirMovimento: reduzirMovimento)
    }

    private var temLivros: Bool {
        if case .pronta = viewModel.estado { return true }
        return false
    }

    @ViewBuilder
    private var estadoAtual: some View {
        switch viewModel.estado {
        case .carregando:
            ProgressView()
        case .vazia:
            VStack(spacing: Espaco.grande) {
                IlustracaoEstanteVazia()
                VStack(spacing: Espaco.pequeno) {
                    Text("Nenhum livro nesta estante")
                        .font(Fonte.tituloEstante)
                    Text("Adicione os livros que ficam neste móvel.")
                        .font(.subheadline)
                        .foregroundColor(Cor.textoSecundario)
                        .multilineTextAlignment(.center)
                }
                Button("Adicionar livro") { adicionando = true }
                    .buttonStyle(EstiloPrincipal())
            }
            .padding(Espaco.padrao)
            .transition(entrada)
        case .pronta(let grupos):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Espaco.grande) {
                    ForEach(grupos, id: \.prateleira) { grupo in
                        prateleira(grupo)
                    }
                }
                .padding(Espaco.padrao)
            }
            .transition(entrada)
        case .erro(let texto):
            MensagemDeErroView(texto: texto) {
                Task { await viewModel.carregar() }
            }
        }
    }

    /// Cabeçalho fora do cartão (como as seções do iOS) e os livros dentro, separados por uma linha que começa
    /// depois da miniatura.
    private func prateleira(_ grupo: GrupoDePrateleira) -> some View {
        VStack(alignment: .leading, spacing: Espaco.pequeno) {
            Text(EstanteViewModel.cabecalho(grupo))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Cor.textoSecundario)
                .padding(.horizontal, Espaco.minimo)
                .accessibilityAddTraits(.isHeader)
                // O VoiceOver leria "Caixa azul ponto 2": falado, com a palavra "livros".
                .accessibilityLabel(
                    "\(EstanteViewModel.nomeDaPrateleira(grupo)), \(Quantidade.livros(grupo.livros.count))"
                )
            VStack(spacing: 0) {
                ForEach(Array(grupo.livros.enumerated()), id: \.element.id) { indice, livro in
                    if indice > 0 {
                        Divider().padding(.leading, Espaco.padrao + larguraDaMiniatura + Espaco.medio)
                    }
                    NavigationLink(value: RotaDoLivro(livroId: livro.id)) {
                        linha(livro)
                    }
                    .buttonStyle(EstiloLinha())
                    .contextMenu {
                        Button {
                            escolhendoCategoriasDe = livro
                        } label: {
                            Label("Categorias…", systemImage: "tag")
                        }
                    }
                    // A linha é lida como um elemento só (os chips não recebem foco próprio): a escolha vira uma ação.
                    .accessibilityAction(named: "Categorias…") { escolhendoCategoriasDe = livro }
                }
            }
            .cartao()
        }
    }

    private func linha(_ livro: Livro) -> some View {
        VStack(alignment: .leading, spacing: Espaco.pequeno) {
        HStack(alignment: .top, spacing: Espaco.medio) {
            MiniaturaDoLivro(livroId: livro.id, carregador: miniaturas, largura: larguraDaMiniatura)
            VStack(alignment: .leading, spacing: 2) {
                Text(livro.titulo)
                    .font(Fonte.tituloLivroNaLista)
                    .foregroundColor(.primary)
                    // Nos tamanhos de acessibilidade, o título inteiro: cortado em 3 linhas, sobravam duas palavras.
                    .lineLimit(tamanhoDoTexto.isAccessibilitySize ? nil : 3)
                if let volume = LivroDetalheViewModel.textoDoVolume(livro) {
                    Text(volume)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                if let secundaria = EstanteViewModel.linhaSecundaria(livro) {
                    Text(secundaria)
                        .font(.subheadline)
                        .foregroundColor(Cor.textoSecundario)
                }
                if !tamanhoDoTexto.isAccessibilitySize {
                    chips(de: livro)
                        .padding(.top, Espaco.pequeno)
                }
            }
            Spacer(minLength: 0)
        }
            // Nos tamanhos de acessibilidade, os chips ocupam a linha inteira, embaixo da miniatura: na coluna ao lado
            // dela, um nome como "Constitucional" não cabia e quebrava no meio da palavra.
            if tamanhoDoTexto.isAccessibilitySize {
                chips(de: livro)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, Espaco.padrao)
        .padding(.vertical, Espaco.medio)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A linha inteira é tocável, não só o texto.
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Os chips do livro, ou o fantasma "+ Categoria" sem nenhuma. Um botão dentro do botão da linha: o toque nos chips
    /// abre a escolha, e no resto da linha, o Detalhe (conferido à mão: o `simctl` não toca na tela).
    private func chips(de livro: Livro) -> some View {
        let categorias = viewModel.categorias(de: livro)
        return Button {
            escolhendoCategoriasDe = livro
        } label: {
            FluxoDeChips {
                if categorias.isEmpty {
                    ChipDeCategoria.fantasma
                } else {
                    ForEach(categorias) { ChipDeCategoria($0) }
                }
            }
        }
        .buttonStyle(EstiloPressao())
    }
}
