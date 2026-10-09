import SwiftUI

/// Tela inicial: as estantes em grade. Versão 0.x (só lógica): componentes nativos, sem estilo decidido.
/// Fica dentro do `NavigationStack` montado em `App/Navegacao`: cada cartão só empurra a `Estante`,
/// e a montagem decide qual tela abrir.
struct InicioView: View {
    @StateObject private var viewModel: InicioViewModel

    /// O que o alerta com campo de texto está pedindo: um nome para uma estante nova ou para renomear uma.
    private enum PedidoDeNome {
        case nova
        case renomear(Estante)
    }

    @State private var pedido: PedidoDeNome?
    @State private var nomeDigitado = ""

    /// Apagar estante: o pedido (lido do banco) e qual das duas folhas está aberta.
    /// Dois `Bool` e um pedido à parte porque, ao tocar numa ação, o SwiftUI fecha a folha e zera o `Bool`
    /// dela; se o pedido estivesse ligado à primeira folha, sumiria antes de a segunda abrir.
    @State private var exclusao: PedidoDeExclusao?
    @State private var confirmandoExclusao = false
    @State private var escolhendoDestino = false

    /// Ação feita ao abrir a tela. Só as capturas do simulador usam (o `simctl` não toca na tela).
    enum AcaoInicial {
        case novaEstante
        case apagar(nomeDaEstante: String)
        case escolherDestino(nomeDaEstante: String)
    }

    private let acaoInicial: AcaoInicial?

    /// `@autoclosure`: o `StateObject` cria o ViewModel uma vez só, mesmo que a tela seja recriada.
    init(viewModel: @autoclosure @escaping () -> InicioViewModel, acaoInicial: AcaoInicial? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.acaoInicial = acaoInicial
    }

    var body: some View {
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
            .task {
                await viewModel.carregar()
                await executar(acaoInicial)
            }
            // Ao voltar da estante, a contagem de livros pode ter mudado.
            .aoVoltar { await viewModel.carregar() }
            .alert(tituloDoPedido, isPresented: pedidoAberto) {
                TextField("Nome da estante", text: $nomeDigitado)
                Button("Cancelar", role: .cancel) {}
                // Sem `.disabled`: no iOS 16 o alerta esconde o botão desabilitado e não o reavalia enquanto se digita
                // (com o campo começando vazio, o "Salvar" nunca aparecia). O ViewModel já ignora nome vazio.
                Button("Salvar") { confirmarNome() }
            }
            .confirmationDialog(
                tituloDaExclusao, isPresented: $confirmandoExclusao, titleVisibility: .visible, presenting: exclusao
            ) { pedido in
                if pedido.podeMover {
                    Button("Mover \(Self.textoDaQuantidade(pedido.quantidadeDeLivros, comArtigo: true)) e apagar…") {
                        escolhendoDestino = true
                    }
                }
                Button(textoDeApagar(pedido), role: .destructive) {
                    Task { await viewModel.apagar(pedido, movendoLivrosPara: nil) }
                }
                Button("Cancelar", role: .cancel) {}
            } message: { pedido in
                Text(mensagemDaExclusao(pedido))
            }
            .confirmationDialog(
                "Mover os livros para…", isPresented: $escolhendoDestino, titleVisibility: .visible, presenting: exclusao
            ) { pedido in
                ForEach(pedido.destinosPossiveis) { destino in
                    Button(destino.nome) {
                        Task { await viewModel.apagar(pedido, movendoLivrosPara: destino) }
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: { pedido in
                Text("A estante \"\(pedido.estante.nome)\" será apagada depois de mover os livros.")
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
                        NavigationLink(value: resumo.estante) {
                            cartao(resumo)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                pedirNome(.renomear(resumo.estante))
                            } label: {
                                Label("Renomear", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                Task { await pedirExclusao(de: resumo.estante) }
                            } label: {
                                Label("Apagar", systemImage: "trash")
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

    /// "1 livro", "3 livros"; com artigo, "o livro", "os 3 livros" (para as frases da confirmação).
    static func textoDaQuantidade(_ quantidade: Int, comArtigo: Bool = false) -> String {
        switch (quantidade, comArtigo) {
        case (1, false): return "1 livro"
        case (1, true): return "o livro"
        case (_, false): return "\(quantidade) livros"
        case (_, true): return "os \(quantidade) livros"
        }
    }

    // MARK: Apagar estante

    private var tituloDaExclusao: String {
        exclusao.map { "Apagar \"\($0.estante.nome)\"?" } ?? ""
    }

    private func textoDeApagar(_ pedido: PedidoDeExclusao) -> String {
        pedido.quantidadeDeLivros == 0
            ? "Apagar estante"
            : "Apagar a estante e \(Self.textoDaQuantidade(pedido.quantidadeDeLivros, comArtigo: true))"
    }

    private func mensagemDaExclusao(_ pedido: PedidoDeExclusao) -> String {
        switch pedido.quantidadeDeLivros {
        case 0: return "A estante está vazia."
        case 1: return "Ela tem 1 livro. Apagado, ele não pode ser recuperado."
        default: return "Ela tem \(pedido.quantidadeDeLivros) livros. Apagados, eles não podem ser recuperados."
        }
    }

    private func pedirExclusao(de estante: Estante) async {
        guard let pedido = await viewModel.pedidoDeExclusao(de: estante) else { return }
        exclusao = pedido
        confirmandoExclusao = true
    }

    private func executar(_ acao: AcaoInicial?) async {
        guard let acao = acao else { return }
        var resumos: [EstanteResumo] = []
        if case .pronto(let lista) = viewModel.estado { resumos = lista }
        let estante = { (nome: String) in resumos.first { $0.estante.nome == nome }?.estante }
        switch acao {
        case .novaEstante:
            pedirNome(.nova)
        case .apagar(let nome):
            if let alvo = estante(nome) { await pedirExclusao(de: alvo) }
        case .escolherDestino(let nome):
            if let alvo = estante(nome), let pedido = await viewModel.pedidoDeExclusao(de: alvo) {
                exclusao = pedido
                escolhendoDestino = true
            }
        }
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
        ComExemplos { NavegacaoView(dependencias: $0) }
            .previewDisplayName("Com estantes")
        ComExemplos(vazio: true) { NavegacaoView(dependencias: $0) }
            .previewDisplayName("Vazio")
    }
}
#endif
