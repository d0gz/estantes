import SwiftUI

/// Os livros de uma estante, em seções por prateleira. Versão 0.x (só lógica).
struct EstanteView: View {
    @StateObject private var viewModel: EstanteViewModel
    @State private var adicionando = false
    /// Cria o ViewModel do formulário; vem da montagem para a tela não precisar conhecer `Dependencias`.
    private let formulario: @MainActor (LivroFormularioViewModel.Modo) -> LivroFormularioViewModel

    init(
        viewModel: @autoclosure @escaping () -> EstanteViewModel,
        formulario: @escaping @MainActor (LivroFormularioViewModel.Modo) -> LivroFormularioViewModel
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.formulario = formulario
    }

    var body: some View {
        conteudo
            .navigationTitle(viewModel.estante.nome)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        adicionando = true
                    } label: {
                        Label("Adicionar livro", systemImage: "plus")
                    }
                }
            }
            // A folha não dispara o `onAppear` da tela de trás ao fechar: a releitura fica no `onDismiss`.
            .sheet(isPresented: $adicionando, onDismiss: { Task { await viewModel.carregar() } }) {
                LivroFormularioView(viewModel: formulario(.novo(estanteId: viewModel.estante.id)))
            }
            .task { await viewModel.carregar() }
            .aoVoltar { await viewModel.carregar() }
    }

    @ViewBuilder
    private var conteudo: some View {
        switch viewModel.estado {
        case .carregando:
            ProgressView()
        case .vazia:
            VStack(spacing: 12) {
                Image(systemName: "book.closed")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Nenhum livro nesta estante")
                    .font(.headline)
            }
        case .pronta(let grupos):
            List {
                ForEach(grupos, id: \.prateleira) { grupo in
                    Section(grupo.prateleira ?? "Sem prateleira") {
                        ForEach(grupo.livros) { livro in
                            NavigationLink(value: RotaDoLivro(livroId: livro.id)) {
                                linha(livro)
                            }
                        }
                    }
                }
            }
        case .erro(let texto):
            MensagemDeErroView(texto: texto) {
                Task { await viewModel.carregar() }
            }
        }
    }

    private func linha(_ livro: Livro) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(livro.titulo)
            if let volume = LivroDetalheViewModel.textoDoVolume(livro) {
                Text(volume)
                    .font(.subheadline)
            }
            if let secundaria = EstanteViewModel.linhaSecundaria(livro) {
                Text(secundaria)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}
