import SwiftUI

/// Formulário de adicionar ou editar um livro, aberto numa folha. O `Form` nativo (e não cartões à mão como no
/// Detalhe): ele já dá apagar e arrastar autores, foco e fuga do teclado, e o cinza com cartões brancos das folhas
/// de edição do iOS, que no escuro se ajusta à folha.
struct LivroFormularioView: View {
    @StateObject private var viewModel: LivroFormularioViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var volumeAberto = false
    @FocusState private var campoEmFoco: WritableKeyPath<RascunhoLivro, String>?

    init(viewModel: @autoclosure @escaping () -> LivroFormularioViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        NavigationStack {
            conteudo
                .navigationTitle(viewModel.titulo)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Salvar") {
                            Task {
                                if await viewModel.salvar() { dismiss() }
                            }
                        }
                        .disabled(viewModel.estado != .pronto || viewModel.salvando)
                    }
                }
        }
        .interactiveDismissDisabled(viewModel.alterado)
        .task {
            await viewModel.carregar()
            volumeAberto = temDadosDeVolume
        }
        .onChange(of: viewModel.rascunho.estanteId) { _ in
            Task { await viewModel.carregarPrateleiras() }
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
        case .pronto:
            formulario
        case .erro(let texto):
            MensagemDeErroView(texto: texto) {
                Task { await viewModel.carregar() }
            }
        }
    }

    private var formulario: some View {
        Form {
            Section {
                campo("Título *", \.titulo, problema: .titulo, fonte: Fonte.tituloLivroNaLista, quebraLinha: true)
                campo("Subtítulo", \.subtitulo, quebraLinha: true)
            }

            Section {
                ForEach(viewModel.rascunho.autores.indices, id: \.self) { posicao in
                    // A vírgula separa o sobrenome, que o cabeçalho do Detalhe usa (regra ABNT).
                    TextField("Nome do autor", text: autor(posicao), prompt: Text("Sobrenome, Nome"))
                        .textContentType(.name)
                }
                .onDelete(perform: viewModel.apagarAutores)
                .onMove(perform: viewModel.moverAutores)
                Button {
                    viewModel.adicionarAutor()
                } label: {
                    Label("Adicionar autor", systemImage: "plus.circle.fill")
                }
            } header: {
                cabecalho("Autores *")
            } footer: {
                erro(.autores)
            }

            Section {
                campo("Editora *", \.editora, problema: .editora)
                campo("Local", \.local)
                campo("Edição", \.edicao, exemplo: "ex.: 3.ª ed.")
                campo("Ano *", \.ano, problema: .ano, teclado: .numberPad)
                campo("Páginas", \.paginas, problema: .paginas, teclado: .numberPad)
                // Números e hífen à vista; o "X" do ISBN-10 fica na tecla "ABC" (o `numberPad` não tem nenhum dos dois).
                campo("ISBN", \.isbn13, problema: .isbn, teclado: .numbersAndPunctuation)
            } header: {
                cabecalho("Publicação")
            }

            Section {
                DisclosureGroup("Volume e coleção", isExpanded: $volumeAberto) {
                    campo("Número do volume", \.volume, problema: .volume, teclado: .numberPad)
                    campo("Como está impresso", \.volumeRotulo, exemplo: "ex.: Tomo XLVIII")
                    campo("Parte", \.parte)
                    campo("Série ou coleção", \.serie)
                    campo("Artigo inicial", \.artigosInicio, problema: .artigosInicio, teclado: .numbersAndPunctuation)
                    campo("Artigo final", \.artigosFim, problema: .artigosFim, teclado: .numbersAndPunctuation)
                }
            }

            Section {
                Picker("Estante", selection: $viewModel.rascunho.estanteId) {
                    ForEach(viewModel.estantes) { estante in
                        Text(estante.nome).tag(estante.id)
                    }
                }
                campo("Prateleira", \.prateleira, exemplo: "ex.: 2ª de cima")
                // Só com o campo em foco: fora dele, as sugestões só ocupariam espaço.
                if campoEmFoco == \.prateleira {
                    ForEach(viewModel.sugestoesDePrateleira, id: \.self) { etiqueta in
                        Button {
                            viewModel.escolherPrateleira(etiqueta)
                            campoEmFoco = nil
                        } label: {
                            Label(etiqueta, systemImage: "arrow.turn.down.right")
                        }
                    }
                }
            } header: {
                cabecalho("Na estante")
            }
        }
    }

    /// Um campo de texto do rascunho. Vazio, o nome (e o exemplo) fica dentro, como placeholder; preenchido, o
    /// placeholder some e o nome passa para cima, pequeno, para "1965" não ficar sem dizer que é o ano. Embaixo,
    /// a mensagem de erro quando houver.
    @ViewBuilder
    private func campo(
        _ nome: String,
        _ caminho: WritableKeyPath<RascunhoLivro, String>,
        exemplo: String? = nil,
        problema: RascunhoLivro.Campo? = nil,
        teclado: UIKeyboardType = .default,
        fonte: Font = .body,
        quebraLinha: Bool = false
    ) -> some View {
        let texto = $viewModel.rascunho[dynamicMember: caminho]
        let placeholder = Text(exemplo.map { "\(nome) (\($0))" } ?? nome)
        VStack(alignment: .leading, spacing: Espaco.minimo) {
            rotulo(nome, visivel: !texto.wrappedValue.isEmpty)
            // Título e subtítulo jurídicos são longos: crescem para baixo em vez de cortar com "…".
            TextField(nome, text: texto, prompt: placeholder, axis: quebraLinha ? .vertical : .horizontal)
                .font(fonte)
                .keyboardType(teclado)
                .focused($campoEmFoco, equals: caminho)
                // A quebra é só visual: o Return (ou um texto colado com linhas) vira espaço e fecha o teclado. Ao
                // salvar, o `RascunhoLivro` ainda junta os espaços repetidos (a regra fica no Domínio, com teste).
                .onChange(of: texto.wrappedValue) { novo in
                    guard quebraLinha, novo.contains(where: \.isNewline) else { return }
                    texto.wrappedValue = novo.split(whereSeparator: \.isNewline).joined(separator: " ")
                    campoEmFoco = nil
                }
            if let problema = problema {
                erro(problema)
            }
        }
        .animacaoSuave(valor: texto.wrappedValue.isEmpty)
    }

    /// O nome pequeno em cima do campo preenchido. Escondido do VoiceOver, que já lê o nome no rótulo do `TextField`.
    @ViewBuilder
    private func rotulo(_ nome: String, visivel: Bool) -> some View {
        if visivel {
            Text(nome)
                .font(.caption)
                .foregroundColor(Cor.textoSecundario)
                .accessibilityHidden(true)
                .transition(.opacity)
        }
    }

    private func cabecalho(_ titulo: String) -> some View {
        Text(titulo).foregroundColor(Cor.textoSecundario)
    }

    @ViewBuilder
    private func erro(_ campo: RascunhoLivro.Campo) -> some View {
        if let problema = viewModel.problemas[campo] {
            Text(LivroFormularioViewModel.mensagem(problema, em: campo))
                .font(.footnote)
                .foregroundColor(Cor.perigo)
        }
    }

    /// Binding por posição que tolera a posição sumir: ao apagar uma linha, o SwiftUI ainda pode
    /// ler a posição antiga uma vez antes de redesenhar, e o acesso direto ao array cairia.
    private func autor(_ posicao: Int) -> Binding<String> {
        Binding(
            get: { posicao < viewModel.rascunho.autores.count ? viewModel.rascunho.autores[posicao] : "" },
            set: { if posicao < viewModel.rascunho.autores.count { viewModel.rascunho.autores[posicao] = $0 } }
        )
    }

    private var temDadosDeVolume: Bool {
        let r = viewModel.rascunho
        return [r.volume, r.volumeRotulo, r.parte, r.serie, r.artigosInicio, r.artigosFim]
            .contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var erroAberto: Binding<Bool> {
        Binding(get: { viewModel.mensagemDeErro != nil }, set: { if !$0 { viewModel.mensagemDeErro = nil } })
    }
}

#if DEBUG
struct LivroFormularioView_Previews: PreviewProvider {
    static var previews: some View {
        ComExemplos { LivroFormularioView(viewModel: $0.fazerLivroFormularioViewModel(modo: .novo(estanteId: DadosDeExemplo.escritorio.id))) }
            .previewDisplayName("Novo")
        ComExemplos { LivroFormularioView(viewModel: $0.fazerLivroFormularioViewModel(modo: .edicao(livroId: DadosDeExemplo.tratadoTomo48))) }
            .previewDisplayName("Editar")
    }
}
#endif
