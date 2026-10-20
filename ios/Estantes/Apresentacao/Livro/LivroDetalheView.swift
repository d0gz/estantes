import SwiftUI

/// Detalhe de um livro: cabeçalho centralizado (miniatura, título em serifa, subtítulo, volume e autores), um cartão
/// por grupo com os campos preenchidos (rótulo em cima, valor embaixo), o cartão "Sumário" (prévia, sumário completo e a
/// folha de edição) e "Apagar livro" no fim, num cartão próprio.
struct LivroDetalheView: View {
    @StateObject private var viewModel: LivroDetalheViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento
    @State private var confirmandoExclusao: Bool
    @State private var editando: Bool
    /// Observado: quando o formulário troca a foto (`trocas`), a tela volta a saber se há foto para ampliar.
    @ObservedObject private var miniaturas: CarregadorDeMiniaturas
    /// Só com foto a miniatura vira botão (a substituta não tem o que ampliar).
    @State private var temFoto = false
    @State private var fotoAberta: UIImage?
    /// Lendo a foto inteira: um segundo toque nesse meio-tempo não lê de novo.
    @State private var abrindoFoto = false
    /// Largura da miniatura do cabeçalho antes do teto: cresce com o texto grande.
    @ScaledMetric(relativeTo: .body) private var larguraBase: CGFloat = 140
    /// Nos tamanhos de acessibilidade ela ocuparia a tela e empurraria o título para baixo.
    private let tetoDaMiniatura: CGFloat = 180
    /// Cria o ViewModel do formulário; vem da montagem para a tela não precisar conhecer `Dependencias`.
    private let formulario: @MainActor (LivroFormularioViewModel.Modo) -> LivroFormularioViewModel
    /// A folha de escolher categorias e a de criar uma nova (dentro dela); também vêm da montagem.
    private let escolha: @MainActor (UUID) -> EscolhaDeCategoriasViewModel
    private let formularioDeCategoria: @MainActor (CategoriaFormularioViewModel.Modo) -> CategoriaFormularioViewModel
    @State private var escolhendoCategorias: Bool
    /// A folha "Editar sumário"; também vem da montagem.
    private let edicaoDoSumario: @MainActor (UUID) -> EditarSumarioViewModel
    @State private var editandoSumario: Bool

    /// - Parameters:
    ///   - abrirConfirmacao: abre a confirmação de apagar logo de início (só as capturas usam).
    ///   - abrirFormulario: abre a edição logo de início (só as capturas usam).
    ///   - abrirCategorias: abre a escolha de categorias logo de início (só as capturas usam).
    ///   - abrirSumario: abre a edição do sumário logo de início (só as capturas usam).
    init(
        viewModel: @autoclosure @escaping () -> LivroDetalheViewModel,
        miniaturas: CarregadorDeMiniaturas,
        formulario: @escaping @MainActor (LivroFormularioViewModel.Modo) -> LivroFormularioViewModel,
        escolha: @escaping @MainActor (UUID) -> EscolhaDeCategoriasViewModel,
        formularioDeCategoria: @escaping @MainActor (CategoriaFormularioViewModel.Modo) -> CategoriaFormularioViewModel,
        edicaoDoSumario: @escaping @MainActor (UUID) -> EditarSumarioViewModel,
        abrirConfirmacao: Bool = false,
        abrirFormulario: Bool = false,
        abrirCategorias: Bool = false,
        abrirSumario: Bool = false
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.miniaturas = miniaturas
        self.formulario = formulario
        self.escolha = escolha
        self.formularioDeCategoria = formularioDeCategoria
        _confirmandoExclusao = State(initialValue: abrirConfirmacao)
        _editando = State(initialValue: abrirFormulario)
        _escolhendoCategorias = State(initialValue: abrirCategorias)
        self.edicaoDoSumario = edicaoDoSumario
        _editandoSumario = State(initialValue: abrirSumario)
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
            .sheet(isPresented: $escolhendoCategorias, onDismiss: { Task { await viewModel.carregar() } }) {
                EscolhaDeCategoriasView(viewModel: escolha(viewModel.livroId), formulario: formularioDeCategoria)
            }
            .sheet(isPresented: $editandoSumario, onDismiss: { Task { await viewModel.carregar() } }) {
                EditarSumarioView(viewModel: edicaoDoSumario(viewModel.livroId))
            }
            .task { await viewModel.carregar() }
            .aoVoltar { await viewModel.carregar() }
            .alertaDeErro($viewModel.mensagemDeErro)
    }

    /// Troca de estado (carregando → livro) com a mola `suave`, como no Inicio e na Estante.
    private var conteudo: some View {
        estadoAtual.animacaoSuave(valor: viewModel.estado)
    }

    private var larguraDaMiniatura: CGFloat {
        min(larguraBase, tetoDaMiniatura)
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
                    ForEach(LivroDetalheViewModel.grupos(de: livro)) { grupo in
                        cartao(grupo)
                    }
                    cartaoDoSumario(livro)
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

    /// Miniatura e, embaixo, o que identifica o livro (dos autores, só os sobrenomes), tudo centralizado (referência: Apple Books).
    private func cabecalho(_ livro: Livro) -> some View {
        let topo = LivroDetalheViewModel.cabecalho(de: livro)
        return VStack(spacing: Espaco.medio) {
            Button {
                guard !abrindoFoto else { return }
                abrindoFoto = true
                Task { @MainActor in
                    fotoAberta = await miniaturas.fotoInteira(doLivro: livro.id)
                    abrindoFoto = false
                }
            } label: {
                MiniaturaDoLivro(livroId: livro.id, carregador: miniaturas, largura: larguraDaMiniatura)
                    .sombraSuave()
            }
            .buttonStyle(EstiloPressao())
            // Dentro do conteúdo, e não em volta da `ScrollView`: uma vista do UIKit envolvendo a tela inteira impedia a
            // barra de navegação de reconhecer a rolagem (sem fundo, o texto passava por baixo do "voltar" e do "Editar").
            .fotoAmpliada($fotoAberta)
            .allowsHitTesting(temFoto)
            .accessibilityHidden(!temFoto)
            .accessibilityLabel("Ampliar foto")
            .task(id: PedidoDaFoto(livroId: livro.id, trocas: miniaturas.trocas)) {
                temFoto = await miniaturas.temFoto(doLivro: livro.id)
            }
            VStack(spacing: Espaco.minimo) {
                Text(topo.titulo)
                    .font(Fonte.tituloLivro)
                    .accessibilityAddTraits(.isHeader)
                if let subtitulo = topo.subtitulo {
                    Text(subtitulo)
                        .font(.subheadline)
                        .foregroundColor(Cor.textoSecundario)
                }
                if let volume = topo.volume {
                    Text(volume)
                        .font(.subheadline.weight(.semibold))
                }
                if let autores = topo.autores {
                    Text(autores)
                        .font(.body)
                        .padding(.top, Espaco.minimo)
                }
            }
            .multilineTextAlignment(.center)
            chipsDeCategoria
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Espaco.pequeno)
    }

    /// As categorias do livro; tocar abre a escolha. Sem nenhuma, o chip fantasma "+ Categoria" convida a escolher.
    private var chipsDeCategoria: some View {
        let categorias = viewModel.categoriasDoLivro
        return Button {
            escolhendoCategorias = true
        } label: {
            FluxoDeChips(centralizado: true) {
                if categorias.isEmpty {
                    ChipDeCategoria.fantasma
                } else {
                    ForEach(categorias) { ChipDeCategoria($0) }
                }
            }
        }
        .buttonStyle(EstiloPressao())
        .accessibilityLabel(categorias.isEmpty ? "Adicionar categoria" : "Categorias: " + categorias.map(\.nome).joined(separator: ", "))
        .accessibilityHint("Toque para escolher as categorias do livro.")
    }

    /// Título do grupo fora do cartão (como na Estante) e os campos dentro, separados por uma linha.
    private func cartao(_ grupo: GrupoDeCampos) -> some View {
        VStack(alignment: .leading, spacing: Espaco.pequeno) {
            Text(grupo.titulo)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Cor.textoSecundario)
                .padding(.horizontal, Espaco.minimo)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                // Pela posição: o mesmo autor digitado duas vezes daria dois campos iguais.
                ForEach(Array(grupo.campos.enumerated()), id: \.offset) { indice, campo in
                    if indice > 0 {
                        Divider().padding(.leading, Espaco.padrao)
                    }
                    linha(campo)
                }
            }
            .cartao()
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

    /// Os primeiros itens (`previaDoSumario`), "Ver sumário completo (N)" quando há mais, e o botão que abre a folha de
    /// edição. Sem sumário, uma frase e "Adicionar sumário".
    private func cartaoDoSumario(_ livro: Livro) -> some View {
        let previa = LivroDetalheViewModel.previaDoSumario(livro.itensSumario)
        return VStack(alignment: .leading, spacing: Espaco.pequeno) {
            Text("Sumário")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Cor.textoSecundario)
                .padding(.horizontal, Espaco.minimo)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                if previa.itens.isEmpty {
                    Text("Com o sumário, a busca acha os temas dentro do livro.")
                        .foregroundColor(Cor.textoSecundario)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Espaco.padrao)
                        .padding(.vertical, Espaco.medio)
                } else {
                    ForEach(previa.itens) { item in
                        ItemDoSumarioView(item)
                            .padding(.horizontal, Espaco.padrao)
                            .padding(.vertical, Espaco.pequeno)
                    }
                }
                if previa.temMais {
                    Divider().padding(.leading, Espaco.padrao)
                    NavigationLink {
                        SumarioCompletoView(itens: livro.itensSumario)
                    } label: {
                        acaoDoSumario("Ver sumário completo (\(previa.total))")
                    }
                    .buttonStyle(EstiloLinha())
                }
                Divider().padding(.leading, Espaco.padrao)
                Button {
                    editandoSumario = true
                } label: {
                    acaoDoSumario(previa.itens.isEmpty ? "Adicionar sumário" : "Editar sumário")
                }
                .buttonStyle(EstiloLinha())
            }
            .padding(.top, previa.itens.isEmpty ? 0 : Espaco.pequeno)
            .cartao()
        }
    }

    private func acaoDoSumario(_ texto: String) -> some View {
        Text(texto)
            .foregroundColor(Cor.destaque)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Espaco.padrao)
            .padding(.vertical, Espaco.medio)
            .contentShape(Rectangle())
    }

    /// No fim da tela, num cartão próprio; a confirmação continua a mesma.
    private var botaoApagar: some View {
        Button(role: .destructive) {
            confirmandoExclusao = true
        } label: {
            Text("Apagar livro")
                .foregroundColor(Cor.perigo)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Espaco.medio)
                .contentShape(Rectangle())
        }
        .buttonStyle(EstiloLinha())
        .cartao()
    }

    private var livroCarregado: Bool {
        if case .pronto = viewModel.estado { return true }
        return false
    }
}

/// Pergunta de novo se há foto quando o formulário troca alguma (`trocas`, do carregador).
private struct PedidoDaFoto: Equatable {
    let livroId: UUID
    let trocas: Int
}
