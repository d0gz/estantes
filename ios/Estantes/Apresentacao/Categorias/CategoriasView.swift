import SwiftUI

/// Gerenciar categorias (menu ⋯ do Inicio): lista em ordem alfabética com o chip e quantos livros têm cada uma.
/// Tocar abre a folha de edição; deslizar apaga, com confirmação. `List` (e não `ScrollView` com cartões) porque
/// o deslizar para apagar vem pronto nela.
struct CategoriasView: View {
    @StateObject private var viewModel: CategoriasViewModel
    private let formulario: (CategoriaFormularioViewModel.Modo) -> CategoriaFormularioViewModel

    /// Qual folha está aberta: criar ou editar uma categoria.
    @State private var folha: CategoriaFormularioViewModel.Modo?
    /// Pedida no botão da folha de edição: a confirmação só abre depois que a folha fecha (duas apresentações
    /// ao mesmo tempo não aparecem).
    @State private var excluirAoFecharFolha: Categoria?
    @State private var exclusao: CategoriaResumo?
    @State private var confirmandoExclusao = false
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    /// Ação feita ao abrir a tela. Só as capturas do simulador usam (o `simctl` não toca na tela).
    enum AcaoInicial {
        case nova
        case editar(nomeDaCategoria: String)
        case apagar(nomeDaCategoria: String)
    }

    private let acaoInicial: AcaoInicial?

    init(
        viewModel: @autoclosure @escaping () -> CategoriasViewModel,
        formulario: @escaping (CategoriaFormularioViewModel.Modo) -> CategoriaFormularioViewModel,
        acaoInicial: AcaoInicial? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.formulario = formulario
        self.acaoInicial = acaoInicial
    }

    var body: some View {
        estadoAtual
            .animacaoSuave(valor: viewModel.estado)
            .navigationTitle("Categorias")
            .toolbar {
                // Como no Inicio: no vazio, a ação única é o botão do estado vazio.
                if temCategorias {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            folha = .nova
                        } label: {
                            Label("Nova categoria", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(item: $folha, onDismiss: aoFecharFolha) { folha in
                CategoriaFormularioView(
                    viewModel: formulario(folha),
                    aoPedirExclusao: { excluirAoFecharFolha = $0 }
                )
            }
            .confirmationDialog(
                tituloDaExclusao, isPresented: $confirmandoExclusao, titleVisibility: .visible, presenting: exclusao
            ) { pedido in
                Button("Apagar categoria", role: .destructive) {
                    Task { await viewModel.apagar(pedido.categoria) }
                }
                Button("Cancelar", role: .cancel) {}
            } message: { pedido in
                Text(CategoriasViewModel.mensagemDaExclusao(pedido.quantidadeDeLivros))
            }
            .alertaDeErro($viewModel.mensagemDeErro)
            .task {
                await viewModel.carregar()
                await executar(acaoInicial)
            }
    }

    @ViewBuilder
    private var estadoAtual: some View {
        switch viewModel.estado {
        case .carregando:
            ProgressView()
        case .vazio:
            VStack(spacing: Espaco.grande) {
                Image(systemName: "tag")
                    .font(.system(size: 56))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(Cor.destaque)
                    .accessibilityHidden(true)
                VStack(spacing: Espaco.pequeno) {
                    Text("Nenhuma categoria ainda")
                        .font(.title3.weight(.semibold))
                    Text("Categorias são etiquetas de assunto. Um livro pode ter várias.")
                        .font(.subheadline)
                        .foregroundColor(Cor.textoSecundario)
                        .multilineTextAlignment(.center)
                }
                Button("Criar a primeira categoria") { folha = .nova }
                    .buttonStyle(EstiloPrincipal())
            }
            .padding(Espaco.padrao)
            .transition(.entrada(reduzirMovimento: reduzirMovimento))
        case .pronto(let resumos):
            List {
                ForEach(resumos) { resumo in
                    Button {
                        folha = .edicao(resumo.categoria)
                    } label: {
                        HStack(spacing: Espaco.medio) {
                            ChipDeCategoria(resumo.categoria)
                            Spacer(minLength: 0)
                            Text(Quantidade.livros(resumo.quantidadeDeLivros))
                                .font(.subheadline)
                                .foregroundColor(Cor.textoSecundario)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await pedirExclusao(de: resumo.categoria) }
                        } label: {
                            Label("Apagar", systemImage: "trash")
                        }
                    }
                    // O deslizar é escondido; o menu de contexto (como nos cartões do Inicio) e o botão na folha de
                    // edição são os caminhos visíveis.
                    .contextMenu {
                        Button {
                            folha = .edicao(resumo.categoria)
                        } label: {
                            Label("Editar", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            Task { await pedirExclusao(de: resumo.categoria) }
                        } label: {
                            Label("Apagar", systemImage: "trash")
                        }
                    }
                }
            }
            // A sombra do Estilo 0 no cartão da lista, sobre o cinza agrupado: o fundo sai da `List` e volta por fora
            // da sombra, que assim só nasce das partes opacas (o cartão branco).
            .scrollContentBackground(.hidden)
            .sombraSuave()
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .transition(.entrada(reduzirMovimento: reduzirMovimento))
        case .erro(let texto):
            MensagemDeErroView(texto: texto) {
                Task { await viewModel.carregar() }
            }
        }
    }

    private var temCategorias: Bool {
        if case .pronto = viewModel.estado { return true }
        return false
    }

    // MARK: Apagar

    private var tituloDaExclusao: String {
        exclusao.map { "Apagar \"\($0.categoria.nome)\"?" } ?? ""
    }

    private func aoFecharFolha() {
        Task {
            await viewModel.carregar()
            if let categoria = excluirAoFecharFolha {
                excluirAoFecharFolha = nil
                await pedirExclusao(de: categoria)
            }
        }
    }

    private func pedirExclusao(de categoria: Categoria) async {
        guard let pedido = await viewModel.pedidoDeExclusao(de: categoria) else { return }
        exclusao = pedido
        confirmandoExclusao = true
    }

    private func executar(_ acao: AcaoInicial?) async {
        guard let acao = acao else { return }
        switch acao {
        case .nova:
            folha = .nova
        case .editar(let nome):
            if let alvo = categoria(chamada: nome) { folha = .edicao(alvo) }
        case .apagar(let nome):
            if let alvo = categoria(chamada: nome) { await pedirExclusao(de: alvo) }
        }
    }

    private func categoria(chamada nome: String) -> Categoria? {
        guard case .pronto(let resumos) = viewModel.estado else { return nil }
        return resumos.first { $0.categoria.nome == nome }?.categoria
    }
}
