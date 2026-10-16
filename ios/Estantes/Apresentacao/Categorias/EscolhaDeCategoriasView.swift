import SwiftUI

/// Folha de escolher as categorias de um livro: todas as categorias com ✓ nas marcadas e, no fim, "Nova categoria",
/// que abre a folha de criar por cima desta (folha sobre folha, como no Lembretes; empurrar o formulário aqui dentro
/// poria uma `NavigationStack` dentro da outra). Grava no "OK"; "Cancelar" descarta.
struct EscolhaDeCategoriasView: View {
    @StateObject private var viewModel: EscolhaDeCategoriasViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var criando = false
    private let formulario: (CategoriaFormularioViewModel.Modo) -> CategoriaFormularioViewModel

    init(
        viewModel: @autoclosure @escaping () -> EscolhaDeCategoriasViewModel,
        formulario: @escaping (CategoriaFormularioViewModel.Modo) -> CategoriaFormularioViewModel
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.formulario = formulario
    }

    var body: some View {
        NavigationStack {
            conteudo
                .navigationTitle("Categorias")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") {
                            Task {
                                if await viewModel.salvar() { dismiss() }
                            }
                        }
                        .disabled(!pronto || viewModel.salvando)
                    }
                }
        }
        .sheet(isPresented: $criando) {
            CategoriaFormularioView(viewModel: formulario(.nova), aoSalvar: viewModel.incluirNova)
        }
        .task { await viewModel.carregar() }
        .alertaDeErro($viewModel.mensagemDeErro)
    }

    private var pronto: Bool {
        if case .pronto = viewModel.estado { return true }
        return false
    }

    @ViewBuilder
    private var conteudo: some View {
        switch viewModel.estado {
        case .carregando:
            ProgressView()
        case .naoEncontrado:
            Text("Livro não encontrado")
                .foregroundColor(Cor.textoSecundario)
        case .pronto(let categorias):
            List {
                Section {
                    ForEach(categorias) { categoria in
                        linha(categoria)
                    }
                    Button {
                        criando = true
                    } label: {
                        Label("Nova categoria", systemImage: "plus")
                    }
                } footer: {
                    if categorias.isEmpty {
                        Text("Nenhuma categoria ainda.")
                            .foregroundColor(Cor.textoSecundario)
                    }
                }
            }
        case .erro(let texto):
            MensagemDeErroView(texto: texto) {
                Task { await viewModel.carregar() }
            }
        }
    }

    private func linha(_ categoria: Categoria) -> some View {
        let marcada = viewModel.marcadas.contains(categoria.id)
        return Button {
            viewModel.alternar(categoria)
        } label: {
            HStack(spacing: Espaco.medio) {
                ChipDeCategoria(categoria)
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundColor(Cor.destaque)
                    .opacity(marcada ? 1 : 0)
            }
        }
        .accessibilityLabel(categoria.nome)
        .accessibilityAddTraits(marcada ? .isSelected : [])
    }
}
