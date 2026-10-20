import SwiftUI
#if DEBUG
import os
#endif

/// Tela inicial: as estantes em grade de cartões (`CartaoDeEstante`) e, sem estantes, a ilustração do vazio.
/// Fica dentro do `NavigationStack` montado em `App/Navegacao`: cada cartão só empurra a `Estante`,
/// e a montagem decide qual tela abrir.
struct InicioView: View {
    @StateObject private var viewModel: InicioViewModel
    @StateObject private var busca: BuscaViewModel
    private let miniaturas: CarregadorDeMiniaturas

    /// O que o alerta com campo de texto está pedindo: um nome para uma estante nova ou para renomear uma.
    private enum PedidoDeNome {
        case nova
        case renomear(Estante)
    }

    @State private var pedido: PedidoDeNome?
    /// A tela "Filtros" da busca, empurrada daqui (fora da troca estantes ↔ resultados). Em folha, tocar num
    /// campo tirava o foco da busca (`isSearching` falso, visto no log) e, ao fechar, voltavam as estantes.
    @State private var mostrandoFiltros: Bool
    @State private var nomeDigitado = ""

    /// Apagar estante: o pedido (lido do banco) e qual das duas folhas está aberta.
    /// Dois `Bool` e um pedido à parte porque, ao tocar numa ação, o SwiftUI fecha a folha e zera o `Bool`
    /// dela; se o pedido estivesse ligado à primeira folha, sumiria antes de a segunda abrir.
    @State private var exclusao: PedidoDeExclusao?
    @State private var confirmandoExclusao = false
    @State private var escolhendoDestino = false

    @Environment(\.dynamicTypeSize) private var tamanhoDoTexto
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    /// Ação feita ao abrir a tela. Só as capturas do simulador usam (o `simctl` não toca na tela).
    enum AcaoInicial {
        case novaEstante
        case apagar(nomeDaEstante: String)
        case escolherDestino(nomeDaEstante: String)
    }

    private let acaoInicial: AcaoInicial?
    /// Empurra a tela de categorias; quem monta a pilha (`App/Navegacao`) decide o que abrir.
    private let abrirCategorias: () -> Void

    /// `@autoclosure`: o `StateObject` cria o ViewModel uma vez só, mesmo que a tela seja recriada.
    init(
        viewModel: @autoclosure @escaping () -> InicioViewModel,
        busca: @autoclosure @escaping () -> BuscaViewModel,
        miniaturas: CarregadorDeMiniaturas,
        abrirCategorias: @escaping () -> Void,
        acaoInicial: AcaoInicial? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        _busca = StateObject(wrappedValue: busca())
        self.miniaturas = miniaturas
        _mostrandoFiltros = State(initialValue: false)
        self.abrirCategorias = abrirCategorias
        self.acaoInicial = acaoInicial
    }

    var body: some View {
        ConteudoComBusca(busca: busca, miniaturas: miniaturas, abrirFiltros: { mostrandoFiltros = true }) { conteudo }
            .navigationTitle("Minhas estantes")
            // Sempre visível, também sem estantes (aí só a dica): esconder a barra a faria pular na tela.
            .searchable(text: $busca.texto, prompt: "Título, autor ou assunto")
            .navigationDestination(isPresented: $mostrandoFiltros) {
                FiltrosDaBuscaView(busca: busca)
            }
            .toolbar {
                // Só com a lista na tela: no vazio, a ação única é o botão do estado vazio (HIG); carregando, o "+"
                // apareceria e sumiria; no erro, não há o que criar. O `if` fica fora do item para não sobrar
                // um item vazio na barra (no iOS 26, uma bolha de vidro sem nada).
                if temEstantes {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            pedirNome(.nova)
                        } label: {
                            Label("Nova estante", systemImage: "plus")
                        }
                    }
                }
                // Também no vazio: dá para criar categorias antes de ter estantes. Por ora só "Categorias";
                // exportar e importar entram aqui na 2.8.
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: abrirCategorias) {
                            Label("Categorias", systemImage: "tag")
                        }
                    } label: {
                        Label("Mais opções", systemImage: "ellipsis.circle")
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
                    Button("Mover \(Quantidade.livros(pedido.quantidadeDeLivros, comArtigo: true)) e apagar…") {
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
                tituloDoDestino, isPresented: $escolhendoDestino, titleVisibility: .visible, presenting: exclusao
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
            .alertaDeErro($viewModel.mensagemDeErro)
    }

    /// Troca de estado (carregando → lista ou vazio) e cartões que entram ou saem: com a mola `suave`.
    private var conteudo: some View {
        estadoAtual.animacaoSuave(valor: viewModel.estado)
    }

    /// Sem cascata: a lista recarrega a cada volta da estante, e a cascata repetida cansaria.
    private var entrada: AnyTransition {
        .entrada(reduzirMovimento: reduzirMovimento)
    }

    private var temEstantes: Bool {
        if case .pronto = viewModel.estado { return true }
        return false
    }

    @ViewBuilder
    private var estadoAtual: some View {
        switch viewModel.estado {
        case .carregando:
            ProgressView()
        case .vazio:
            VStack(spacing: Espaco.grande) {
                IlustracaoEstanteVazia()
                VStack(spacing: Espaco.pequeno) {
                    Text("Nenhuma estante ainda")
                        .font(Fonte.tituloEstante)
                    Text("Crie uma estante para cada móvel onde ficam os seus livros.")
                        .font(.subheadline)
                        .foregroundColor(Cor.textoSecundario)
                        .multilineTextAlignment(.center)
                }
                Button("Criar a primeira estante") { pedirNome(.nova) }
                    .buttonStyle(EstiloPrincipal())
            }
            .padding(Espaco.padrao)
            .transition(entrada)
        case .pronto(let resumos):
            ScrollView {
                LazyVGrid(columns: colunas, spacing: Espaco.padrao) {
                    ForEach(resumos) { resumo in
                        NavigationLink(value: resumo.estante) {
                            CartaoDeEstante(
                                nome: resumo.estante.nome,
                                detalhe: Quantidade.livros(resumo.quantidadeDeLivros)
                            )
                        }
                        .buttonStyle(EstiloCartao())
                        .transition(entrada)
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
                .padding(Espaco.padrao)
            }
            .transition(entrada)
        case .erro(let texto):
            MensagemDeErroView(texto: texto) {
                Task { await viewModel.carregar() }
            }
        }
    }

    /// Duas colunas; uma só nos tamanhos de texto de acessibilidade, em que o nome da estante não cabe numa coluna
    /// estreita.
    private var colunas: [GridItem] {
        let quantidade = tamanhoDoTexto.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Espaco.padrao), count: quantidade)
    }

    // MARK: Apagar estante

    private var tituloDaExclusao: String {
        exclusao.map { "Apagar \"\($0.estante.nome)\"?" } ?? ""
    }

    /// Repete a quantidade da primeira folha ("Mover os 6 livros para…"): confirma quais livros vão.
    private var tituloDoDestino: String {
        exclusao.map { "Mover \(Quantidade.livros($0.quantidadeDeLivros, comArtigo: true)) para…" } ?? ""
    }

    private func textoDeApagar(_ pedido: PedidoDeExclusao) -> String {
        pedido.quantidadeDeLivros == 0
            ? "Apagar estante"
            : "Apagar a estante e \(Quantidade.livros(pedido.quantidadeDeLivros, comArtigo: true))"
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

/// Troca as estantes pelos resultados enquanto a busca está ativa. Vista à parte porque o `isSearching`
/// só chega a quem está dentro do `.searchable`, e não à própria `InicioView`, que o aplica.
private struct ConteudoComBusca<Estantes: View>: View {
    @ObservedObject var busca: BuscaViewModel
    let miniaturas: CarregadorDeMiniaturas
    let abrirFiltros: () -> Void
    @ViewBuilder let estantes: () -> Estantes
    @Environment(\.isSearching) private var buscando

    var body: some View {
        Group {
            if buscando {
                ResultadosDaBuscaView(busca: busca, miniaturas: miniaturas, abrirFiltros: abrirFiltros)
            } else {
                estantes()
            }
        }
        #if DEBUG
        // Diagnóstico da folha que fechava (a conferir com a tela empurrada; sai no fechamento da 2.7):
        // `log stream --predicate 'subsystem == "com.ricardo.estantes"'`.
        .onChange(of: buscando) { valor in
            Logger(subsystem: "com.ricardo.estantes", category: "busca").debug("isSearching = \(valor)")
        }
        #endif
    }
}
