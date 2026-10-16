import SwiftUI

/// Gerenciar categorias (menu ⋯ do Inicio): lista em ordem alfabética com o chip e quantos livros têm cada uma.
/// Tocar abre a folha de edição; deslizar apaga, com confirmação. `List` (e não `ScrollView` com cartões) porque
/// o deslizar para apagar vem pronto nela.
struct CategoriasView: View {
    @StateObject private var viewModel: CategoriasViewModel
    private let formulario: (CategoriaFormularioViewModel.Modo) -> CategoriaFormularioViewModel

    /// Qual folha está aberta: criar ou editar uma categoria.
    private enum Folha: Identifiable {
        case nova
        case edicao(Categoria)

        var id: String {
            switch self {
            case .nova: return "nova"
            case .edicao(let categoria): return categoria.id.uuidString
            }
        }

        var modo: CategoriaFormularioViewModel.Modo {
            switch self {
            case .nova: return .nova
            case .edicao(let categoria): return .edicao(categoria)
            }
        }
    }

    @State private var folha: Folha?
    @State private var exclusao: ExclusaoDeCategoria?
    @State private var confirmandoExclusao = false
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    /// Ação feita ao abrir a tela. Só as capturas do simulador usam (o `simctl` não toca na tela).
    enum AcaoInicial {
        case nova
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
            .sheet(item: $folha, onDismiss: { Task { await viewModel.carregar() } }) { folha in
                CategoriaFormularioView(viewModel: formulario(folha.modo))
            }
            .confirmationDialog(
                tituloDaExclusao, isPresented: $confirmandoExclusao, titleVisibility: .visible, presenting: exclusao
            ) { pedido in
                Button("Apagar categoria", role: .destructive) {
                    Task { await viewModel.apagar(pedido.categoria) }
                }
                Button("Cancelar", role: .cancel) {}
            } message: { pedido in
                Text(Self.mensagemDaExclusao(pedido.quantidadeDeLivros))
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
                }
            }
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

    /// Os livros ficam; só perdem a etiqueta (nullify). A frase diz isso, para "apagar" não assustar.
    static func mensagemDaExclusao(_ quantidade: Int) -> String {
        switch quantidade {
        case 0: return "Nenhum livro tem esta categoria."
        case 1: return "1 livro perde esta categoria. O livro continua na estante."
        default: return "\(quantidade) livros perdem esta categoria. Os livros continuam nas estantes."
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
        case .apagar(let nome):
            guard case .pronto(let resumos) = viewModel.estado,
                  let alvo = resumos.first(where: { $0.categoria.nome == nome }) else { return }
            await pedirExclusao(de: alvo.categoria)
        }
    }
}
