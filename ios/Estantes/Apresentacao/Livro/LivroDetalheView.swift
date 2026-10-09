import SwiftUI

/// Detalhe de um livro: os campos preenchidos e "Apagar livro". Versão 0.x (só lógica).
struct LivroDetalheView: View {
    @StateObject private var viewModel: LivroDetalheViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmandoExclusao: Bool

    /// - Parameter abrirConfirmacao: abre a confirmação de apagar logo de início (só as capturas usam).
    init(viewModel: @autoclosure @escaping () -> LivroDetalheViewModel, abrirConfirmacao: Bool = false) {
        _viewModel = StateObject(wrappedValue: viewModel())
        _confirmandoExclusao = State(initialValue: abrirConfirmacao)
    }

    var body: some View {
        conteudo
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // A edição chega no 2.4d.
                    Button("Editar") {}
                        .disabled(true)
                }
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

    private var erroAberto: Binding<Bool> {
        Binding(get: { viewModel.mensagemDeErro != nil }, set: { if !$0 { viewModel.mensagemDeErro = nil } })
    }
}
