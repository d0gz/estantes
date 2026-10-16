import SwiftUI

/// Folha de criar ou editar uma categoria: nome, cor (grade com as 10 da paleta) e a prévia do chip.
/// `Form` nativo, como o formulário do livro (exceção ao Estilo 0 registrada no PLANO).
struct CategoriaFormularioView: View {
    @StateObject private var viewModel: CategoriaFormularioViewModel
    @Environment(\.dismiss) private var dismiss
    /// Recebe a categoria gravada antes de a folha fechar (a escolha no livro marca a nova).
    private let aoSalvar: (Categoria) -> Void
    @ScaledMetric(relativeTo: .body) private var diametro: CGFloat = 36

    init(viewModel: @autoclosure @escaping () -> CategoriaFormularioViewModel, aoSalvar: @escaping (Categoria) -> Void = { _ in }) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.aoSalvar = aoSalvar
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
                                if let categoria = await viewModel.salvar() {
                                    aoSalvar(categoria)
                                    dismiss()
                                }
                            }
                        }
                        .disabled(viewModel.estado != .pronto || viewModel.salvando)
                    }
                }
        }
        .task { await viewModel.carregar() }
        .alertaDeErro($viewModel.mensagemDeErro)
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
                TextField("Nome", text: $viewModel.nome, prompt: Text("Nome (ex.: Direito tributário)"))
                    .submitLabel(.done)
            } footer: {
                if let problema = viewModel.problemaDoNome {
                    Text(problema).font(.footnote).foregroundColor(Cor.perigo)
                }
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: diametro + Espaco.medio), spacing: Espaco.medio)],
                          spacing: Espaco.medio) {
                    ForEach(CorCategoria.allCases, id: \.self) { cor in
                        circulo(cor)
                    }
                }
                .padding(.vertical, Espaco.pequeno)
            } header: {
                Text("Cor").foregroundColor(Cor.textoSecundario)
            }

            Section {
                ChipDeCategoria(Categoria(nome: nomeDaPrevia, cor: viewModel.cor))
                    .animacaoSuave(valor: viewModel.cor)
            } header: {
                Text("Prévia").foregroundColor(Cor.textoSecundario)
            }
        }
    }

    private var nomeDaPrevia: String {
        let aparado = viewModel.nome.trimmingCharacters(in: .whitespacesAndNewlines)
        return aparado.isEmpty ? "Nome da categoria" : aparado
    }

    /// Círculo na cor viva; a escolhida ganha um anel em `.primary` e o ✓ (forma e símbolo, não só a cor).
    private func circulo(_ cor: CorCategoria) -> some View {
        let escolhida = viewModel.cor == cor
        return Button {
            viewModel.cor = cor
        } label: {
            Circle()
                .fill(Color(uiColor: Paleta.categoria(cor).viva))
                .frame(width: diametro, height: diametro)
                .overlay {
                    if escolhida {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1)
                    }
                }
                .padding(3)
                .overlay(Circle().strokeBorder(escolhida ? Color.primary : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cor.nomeNaTela)
        .accessibilityAddTraits(escolhida ? .isSelected : [])
    }
}
