import SwiftUI

/// Tela inicial: as estantes em grade. Versão 0.x (só lógica): componentes nativos, sem estilo decidido.
struct InicioView: View {
    @StateObject private var viewModel: InicioViewModel

    /// O que o alerta com campo de texto está pedindo: um nome para uma estante nova ou para renomear uma.
    private enum PedidoDeNome {
        case nova
        case renomear(Estante)
    }

    @State private var pedido: PedidoDeNome?
    @State private var nomeDigitado = ""

    /// `@autoclosure`: o `StateObject` cria o ViewModel uma vez só, mesmo que a tela seja recriada.
    init(viewModel: @autoclosure @escaping () -> InicioViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        NavigationStack {
            conteudo
                .navigationTitle("Minhas estantes")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            pedirNome(.nova)
                        } label: {
                            Label("Nova estante", systemImage: "plus")
                        }
                    }
                }
        }
        .task { await viewModel.carregar() }
        .alert(tituloDoPedido, isPresented: pedidoAberto) {
            TextField("Nome da estante", text: $nomeDigitado)
            Button("Cancelar", role: .cancel) {}
            // Sem `.disabled`: no iOS 16 o alerta esconde o botão desabilitado e não o reavalia enquanto se digita
            // (com o campo começando vazio, o "Salvar" nunca aparecia). O ViewModel já ignora nome vazio.
            Button("Salvar") { confirmarNome() }
        }
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
        case .vazio:
            VStack(spacing: 16) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
                Text("Nenhuma estante ainda")
                    .font(.headline)
                Button("Criar a primeira estante") { pedirNome(.nova) }
                    .buttonStyle(.borderedProminent)
            }
        case .pronto(let resumos):
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(resumos) { resumo in
                        cartao(resumo)
                            .contextMenu {
                                Button {
                                    pedirNome(.renomear(resumo.estante))
                                } label: {
                                    Label("Renomear", systemImage: "pencil")
                                }
                            }
                    }
                }
                .padding()
            }
        case .erro(let texto):
            MensagemDeErroView(texto: texto) {
                Task { await viewModel.carregar() }
            }
        }
    }

    private func cartao(_ resumo: EstanteResumo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(resumo.estante.nome)
                .font(.headline)
                .lineLimit(2)
            Text(Self.textoDaQuantidade(resumo.quantidadeDeLivros))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    static func textoDaQuantidade(_ quantidade: Int) -> String {
        quantidade == 1 ? "1 livro" : "\(quantidade) livros"
    }

    // MARK: Alerta do nome

    private var tituloDoPedido: String {
        switch pedido {
        case .renomear: return "Renomear estante"
        case .nova, nil: return "Nova estante"
        }
    }

    /// O `.alert` quer um `Binding<Bool>`; este é derivado do `pedido`, para não haver dois estados a sincronizar.
    private var pedidoAberto: Binding<Bool> {
        Binding(get: { pedido != nil }, set: { if !$0 { pedido = nil } })
    }

    private var erroAberto: Binding<Bool> {
        Binding(get: { viewModel.mensagemDeErro != nil }, set: { if !$0 { viewModel.mensagemDeErro = nil } })
    }

    private func pedirNome(_ novoPedido: PedidoDeNome) {
        if case .renomear(let estante) = novoPedido {
            nomeDigitado = estante.nome
        } else {
            nomeDigitado = ""
        }
        pedido = novoPedido
    }

    private func confirmarNome() {
        guard let pedidoAtual = pedido else { return }
        let nome = nomeDigitado
        Task {
            switch pedidoAtual {
            case .nova: await viewModel.criarEstante(nome: nome)
            case .renomear(let estante): await viewModel.renomear(estante, para: nome)
            }
        }
    }
}

#if DEBUG
struct InicioView_Previews: PreviewProvider {
    static var previews: some View {
        ComExemplos { InicioView(viewModel: $0.fazerInicioViewModel()) }
            .previewDisplayName("Com estantes")
        ComExemplos(vazio: true) { InicioView(viewModel: $0.fazerInicioViewModel()) }
            .previewDisplayName("Vazio")
    }
}
#endif
