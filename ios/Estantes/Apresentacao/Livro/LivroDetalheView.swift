import SwiftUI

/// Detalhe de um livro: cabeçalho centralizado (miniatura, título em serifa, subtítulo, volume e autores), um cartão
/// por seção com os campos preenchidos (rótulo em cima, valor embaixo) e "Apagar livro" no fim, num cartão próprio.
struct LivroDetalheView: View {
    @StateObject private var viewModel: LivroDetalheViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento
    @State private var confirmandoExclusao: Bool
    @State private var editando: Bool
    private let miniaturas: CarregadorDeMiniaturas
    /// Largura da miniatura do cabeçalho: cresce com o texto grande.
    @ScaledMetric(relativeTo: .body) private var larguraEscalada: CGFloat = 140
    /// Cria o ViewModel do formulário; vem da montagem para a tela não precisar conhecer `Dependencias`.
    private let formulario: @MainActor (LivroFormularioViewModel.Modo) -> LivroFormularioViewModel

    /// - Parameters:
    ///   - abrirConfirmacao: abre a confirmação de apagar logo de início (só as capturas usam).
    ///   - abrirFormulario: abre a edição logo de início (só as capturas usam).
    init(
        viewModel: @autoclosure @escaping () -> LivroDetalheViewModel,
        miniaturas: CarregadorDeMiniaturas,
        formulario: @escaping @MainActor (LivroFormularioViewModel.Modo) -> LivroFormularioViewModel,
        abrirConfirmacao: Bool = false,
        abrirFormulario: Bool = false
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.miniaturas = miniaturas
        self.formulario = formulario
        _confirmandoExclusao = State(initialValue: abrirConfirmacao)
        _editando = State(initialValue: abrirFormulario)
    }

    var body: some View {
        conteudo
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Editar") { editando = true }
                        .disabled(!livroCarregado)
                }
            }
            .sheet(isPresented: $editando, onDismiss: { Task { await viewModel.carregar() } }) {
                LivroFormularioView(viewModel: formulario(.edicao(livroId: viewModel.livroId)))
            }
            .task { await viewModel.carregar() }
            .aoVoltar { await viewModel.carregar() }
            .alert("Algo deu errado", isPresented: erroAberto) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.mensagemDeErro ?? "")
            }
    }

    /// Troca de estado (carregando → livro) com a mola `suave`, como no Inicio e na Estante.
    private var conteudo: some View {
        estadoAtual.animacaoSuave(valor: viewModel.estado)
    }

    /// Com teto de 180 pt: nos tamanhos de acessibilidade ela ocuparia a tela e empurraria o título para baixo.
    private var larguraDaMiniatura: CGFloat {
        min(larguraEscalada, 180)
    }

    @ViewBuilder
    private var estadoAtual: some View {
        switch viewModel.estado {
        case .carregando:
            ProgressView()
        case .naoEncontrado:
            Text("Livro não encontrado")
                .foregroundColor(Cor.textoSecundario)
        case .pronto(let livro):
            ScrollView {
                VStack(spacing: Espaco.grande) {
                    cabecalho(livro)
                    ForEach(LivroDetalheViewModel.secoes(de: livro)) { secao in
                        cartao(secao)
                    }
                    botaoApagar
                }
                .padding(Espaco.padrao)
            }
            .transition(.entrada(reduzirMovimento: reduzirMovimento))
            .confirmationDialog(
                "Apagar \"\(livro.titulo)\"?", isPresented: $confirmandoExclusao, titleVisibility: .visible
            ) {
                Button("Apagar livro", role: .destructive) {
                    Task {
                        if await viewModel.apagar() { dismiss() }
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("O livro não pode ser recuperado depois de apagado.")
            }
        case .erro(let texto):
            MensagemDeErroView(texto: texto) {
                Task { await viewModel.carregar() }
            }
        }
    }

    /// Miniatura e, embaixo, o que identifica o livro (dos autores, só o primeiro), tudo centralizado (referência: Apple Books).
    private func cabecalho(_ livro: Livro) -> some View {
        let cabecalho = LivroDetalheViewModel.cabecalho(de: livro)
        return VStack(spacing: Espaco.medio) {
            MiniaturaDoLivro(livroId: livro.id, carregador: miniaturas, largura: larguraDaMiniatura)
                .sombraSuave()
            VStack(spacing: Espaco.minimo) {
                Text(cabecalho.titulo)
                    .font(Fonte.tituloLivro)
                    .accessibilityAddTraits(.isHeader)
                if let subtitulo = cabecalho.subtitulo {
                    Text(subtitulo)
                        .font(.subheadline)
                        .foregroundColor(Cor.textoSecundario)
                }
                if let volume = cabecalho.volume {
                    Text(volume)
                        .font(.subheadline.weight(.semibold))
                }
                if let autores = cabecalho.autores {
                    Text(autores)
                        .font(.body)
                        .padding(.top, Espaco.minimo)
                }
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Espaco.pequeno)
    }

    /// Título da seção fora do cartão (como na Estante) e os campos dentro, separados por uma linha.
    private func cartao(_ secao: SecaoDoLivro) -> some View {
        VStack(alignment: .leading, spacing: Espaco.pequeno) {
            Text(secao.titulo)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Cor.textoSecundario)
                .padding(.horizontal, Espaco.minimo)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(secao.campos.enumerated()), id: \.element.id) { indice, campo in
                    if indice > 0 {
                        Divider().padding(.leading, Espaco.padrao)
                    }
                    linha(campo)
                }
            }
            .background(Cor.cartao)
            .cantos(Raio.grande)
            .sombraSuave()
        }
    }

    /// Rótulo pequeno em cima e valor embaixo: valores longos e texto grande quebram sem espremer o rótulo.
    private func linha(_ campo: CampoDoLivro) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let rotulo = campo.rotulo {
                Text(rotulo)
                    .font(.caption)
                    .foregroundColor(Cor.textoSecundario)
            }
            Text(campo.valor)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Espaco.padrao)
        .padding(.vertical, Espaco.medio)
        .accessibilityElement(children: .combine)
    }

    /// No fim da tela, num cartão próprio; a confirmação continua a mesma.
    private var botaoApagar: some View {
        Button(role: .destructive) {
            confirmandoExclusao = true
        } label: {
            Text("Apagar livro")
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Espaco.medio)
                .contentShape(Rectangle())
        }
        .buttonStyle(EstiloLinha())
        .background(Cor.cartao)
        .cantos(Raio.grande)
        .sombraSuave()
    }

    private var livroCarregado: Bool {
        if case .pronto = viewModel.estado { return true }
        return false
    }

    private var erroAberto: Binding<Bool> {
        Binding(get: { viewModel.mensagemDeErro != nil }, set: { if !$0 { viewModel.mensagemDeErro = nil } })
    }
}
