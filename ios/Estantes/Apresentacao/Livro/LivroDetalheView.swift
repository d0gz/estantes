import SwiftUI

/// Detalhe de um livro: os campos preenchidos e "Apagar livro". Versão 0.x (só lógica).
struct LivroDetalheView: View {
    @StateObject private var viewModel: LivroDetalheViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmandoExclusao: Bool
    @State private var editando: Bool
    /// Cria o ViewModel do formulário; vem da montagem para a tela não precisar conhecer `Dependencias`.
    private let formulario: @MainActor (LivroFormularioViewModel.Modo) -> LivroFormularioViewModel

    /// - Parameters:
    ///   - abrirConfirmacao: abre a confirmação de apagar logo de início (só as capturas usam).
    ///   - abrirFormulario: abre a edição logo de início (só as capturas usam).
    init(
        viewModel: @autoclosure @escaping () -> LivroDetalheViewModel,
        formulario: @escaping @MainActor (LivroFormularioViewModel.Modo) -> LivroFormularioViewModel,
        abrirConfirmacao: Bool = false,
        abrirFormulario: Bool = false
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
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

    @ViewBuilder
    private var conteudo: some View {
        switch viewModel.estado {
        case .carregando:
            ProgressView()
        case .naoEncontrado:
            Text("Livro não encontrado")
                .foregroundColor(.secondary)
        case .pronto(let livro):
            List {
                Section {
                    Text(livro.titulo)
                        .font(.title2.bold())
                }
                ForEach(LivroDetalheViewModel.secoes(de: livro)) { secao in
                    Section(secao.titulo) {
                        ForEach(secao.campos) { campo in
                            LabeledContent(campo.rotulo) {
                                Text(campo.valor)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
                Section {
                    Button("Apagar livro", role: .destructive) {
                        confirmandoExclusao = true
                    }
                }
            }
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

    private var livroCarregado: Bool {
        if case .pronto = viewModel.estado { return true }
        return false
    }

    private var erroAberto: Binding<Bool> {
        Binding(get: { viewModel.mensagemDeErro != nil }, set: { if !$0 { viewModel.mensagemDeErro = nil } })
    }
}
