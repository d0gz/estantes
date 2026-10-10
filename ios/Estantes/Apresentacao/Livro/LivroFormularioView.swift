import SwiftUI

/// Formulário de adicionar ou editar um livro, aberto numa folha. Versão 0.x (só lógica).
struct LivroFormularioView: View {
    @StateObject private var viewModel: LivroFormularioViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var volumeAberto = false

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
                campo("Título *", \.titulo, problema: .titulo)
                campo("Subtítulo", \.subtitulo)
            }

            Section {
                ForEach(viewModel.rascunho.autores.indices, id: \.self) { posicao in
                    TextField("Nome do autor", text: autor(posicao))
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
                Text("Autores *")
            } footer: {
                erro(.autores)
            }

            Section("Publicação") {
                campo("Editora *", \.editora, problema: .editora)
                campo("Local", \.local)
                campo("Edição (ex.: 3.ª ed.)", \.edicao)
                campo("Ano *", \.ano, problema: .ano, teclado: .numberPad)
                campo("Páginas", \.paginas, problema: .paginas, teclado: .numberPad)
                campo("ISBN", \.isbn13, teclado: .numberPad)
            }

            Section {
                DisclosureGroup("Volume e coleção", isExpanded: $volumeAberto) {
                    campo("Número do volume", \.volume, problema: .volume, teclado: .numberPad)
                    campo("Como está impresso (ex.: Tomo XLVIII)", \.volumeRotulo)
                    campo("Parte", \.parte)
                    campo("Série ou coleção", \.serie)
                    campo("Artigo inicial", \.artigosInicio, problema: .artigosInicio, teclado: .numbersAndPunctuation)
                    campo("Artigo final", \.artigosFim, problema: .artigosFim, teclado: .numbersAndPunctuation)
                }
            }

            Section("Na estante") {
                Picker("Estante", selection: $viewModel.rascunho.estanteId) {
                    ForEach(viewModel.estantes) { estante in
                        Text(estante.nome).tag(estante.id)
                    }
                }
                campo("Prateleira (ex.: 2ª de cima)", \.prateleira)
            }
        }
    }

    /// Um campo de texto do rascunho, com a mensagem de erro embaixo quando houver.
    @ViewBuilder
    private func campo(
        _ rotulo: String,
        _ caminho: WritableKeyPath<RascunhoLivro, String>,
        problema campo: RascunhoLivro.Campo? = nil,
        teclado: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(rotulo, text: $viewModel.rascunho[dynamicMember: caminho])
                .keyboardType(teclado)
            if let campo = campo {
                erro(campo)
            }
        }
    }

    @ViewBuilder
    private func erro(_ campo: RascunhoLivro.Campo) -> some View {
        if let problema = viewModel.problemas[campo] {
            Text(LivroFormularioViewModel.mensagem(problema, em: campo))
                .font(.footnote)
                .foregroundColor(.red)
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
