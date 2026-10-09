import SwiftUI

/// Os livros de uma estante, em seções por prateleira. Versão 0.x (só lógica).
struct EstanteView: View {
    @StateObject private var viewModel: EstanteViewModel

    init(viewModel: @autoclosure @escaping () -> EstanteViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        conteudo
            .navigationTitle(viewModel.estante.nome)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // O formulário chega no 2.4d.
                    Button {} label: {
                        Label("Adicionar livro", systemImage: "plus")
                    }
                    .disabled(true)
                }
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
