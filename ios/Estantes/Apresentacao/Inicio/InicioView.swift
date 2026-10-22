import SwiftUI
import UniformTypeIdentifiers

/// Tela inicial: as estantes em grade de cartões (`CartaoDeEstante`) e, sem estantes, a ilustração do vazio.
/// Fica dentro do `NavigationStack` montado em `App/Navegacao`: cada cartão só empurra a `Estante`,
/// e a montagem decide qual tela abrir.
struct InicioView: View {
    @StateObject private var viewModel: InicioViewModel
    /// Exportar, importar e (nos builds com exemplos) carregar os dados de exemplo, no menu ⋯.
    @StateObject private var exportacao: ExportacaoViewModel

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

    /// Importação: o seletor de arquivos e a pergunta "mesclar ou substituir". Um `Bool` próprio, e não ligado
    /// à importação pendente, pelo mesmo motivo da exclusão: ao tocar numa ação, o SwiftUI zera o `Bool` antes
    /// de a ação usar o que foi lido.
    @State private var escolhendoArquivo = false
    @State private var confirmandoImportacao = false

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
        exportacao: @autoclosure @escaping () -> ExportacaoViewModel,
        abrirCategorias: @escaping () -> Void,
        acaoInicial: AcaoInicial? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        _exportacao = StateObject(wrappedValue: exportacao())
        self.abrirCategorias = abrirCategorias
        self.acaoInicial = acaoInicial
    }

    var body: some View {
        // Sempre à vista, também sem estantes. Um botão, e não `.searchable`: a busca é uma tela própria
        // (no iOS 16, empurrar o Detalhe ou os Filtros desligava o `.searchable` da tela raiz).
        // Numa pilha acima da lista, e não por cima dela (`safeAreaInset`): ali o título grande encolhia ao rolar e
        // passava sobre o botão; sem a lista logo abaixo da barra, o título fica parado e só os cartões rolam.
        VStack(spacing: 0) {
            BotaoDeBusca()
                .padding(.horizontal, Espaco.padrao)
                .padding(.bottom, Espaco.pequeno)
            conteudo
                .frame(maxHeight: .infinity)
        }
            .navigationTitle("Minhas estantes")
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
                // Também no vazio: dá para criar categorias antes de ter estantes, e importar um backup num
                // aparelho novo.
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: abrirCategorias) {
                            Label("Categorias", systemImage: "tag")
                        }
                        Divider()
                        Button {
                            Task { await exportacao.exportarBiblioteca() }
                        } label: {
                            Label("Exportar biblioteca", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            escolhendoArquivo = true
                        } label: {
                            Label("Importar…", systemImage: "square.and.arrow.down")
                        }
                        if exportacao.podeCarregarExemplos {
                            Divider()
                            Button {
                                Task {
                                    if await exportacao.carregarExemplos() { await viewModel.carregar() }
                                }
                            } label: {
                                Label("Carregar dados de exemplo", systemImage: "books.vertical")
                            }
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
            .modifier(ExportacaoEImportacao(
                exportacao: exportacao,
                escolhendoArquivo: $escolhendoArquivo,
                confirmandoImportacao: $confirmandoImportacao,
                aoImportar: { await viewModel.carregar() }
            ))
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

/// Folha de compartilhar, seletor de arquivos, pergunta "mesclar ou substituir" e o aviso do resultado.
/// À parte do `body` do Inicio, que já tem os alertas das estantes (e o Xcode 14 demora a conferir um `body` longo).
private struct ExportacaoEImportacao: ViewModifier {
    @ObservedObject var exportacao: ExportacaoViewModel
    @Binding var escolhendoArquivo: Bool
    @Binding var confirmandoImportacao: Bool
    let aoImportar: @MainActor () async -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $exportacao.arquivoExportado) { arquivo in
                FolhaDeCompartilhar(url: arquivo.url)
            }
            .fileImporter(isPresented: $escolhendoArquivo, allowedContentTypes: [.json]) { resultado in
                switch resultado {
                case .success(let url): exportacao.lerArquivo(url)
                case .failure: exportacao.arquivoNaoAberto()
                }
            }
            .onChange(of: exportacao.importacaoPendente) { pendente in
                confirmandoImportacao = pendente != nil
            }
            .confirmationDialog(
                "Importar biblioteca", isPresented: $confirmandoImportacao, titleVisibility: .visible,
                presenting: exportacao.importacaoPendente
            ) { _ in
                Button("Mesclar") { importar(.mesclar) }
                Button("Substituir tudo", role: .destructive) { importar(.substituir) }
                Button("Cancelar", role: .cancel) { exportacao.cancelarImportacao() }
            } message: { pendente in
                Text("\(pendente.resumo)\n\nMesclar junta o arquivo à biblioteca. Substituir tudo apaga o que não "
                     + "estiver no arquivo.")
            }
            .alert(
                exportacao.aviso?.titulo ?? "", isPresented: avisoAberto, presenting: exportacao.aviso
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { aviso in
                Text(aviso.mensagem)
            }
    }

    private var avisoAberto: Binding<Bool> {
        Binding(get: { exportacao.aviso != nil }, set: { if !$0 { exportacao.aviso = nil } })
    }

    private func importar(_ modo: ImportarBiblioteca.Modo) {
        Task {
            if await exportacao.confirmarImportacao(modo) { await aoImportar() }
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
