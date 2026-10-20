import SwiftUI

/// Folha "Editar sumário" (decisão de 20/10): a lista só mostra os itens; "Adicionar item" ou tocar num item empurra a
/// `EdicaoDoItemView`. Deslizar para a direita muda o nível, para a esquerda apaga; segurar e arrastar reordena; o menu
/// de contexto tem "Inserir abaixo". Grava no "Salvar"; "Cancelar" descarta. Com mudanças, arrastar para fechar fica
/// bloqueado, como no formulário do livro.
///
/// A tela de item é empurrada por `navigationDestination(isPresented:)`, não por `navigationDestination(for:)` com um
/// caminho: no iOS 16, o destino por tipo numa folha aberta de dentro da pilha principal (`NavegacaoView`) põe o app em
/// laço (CPU a 100%, Detalhe preso no "carregando"; diagnosticado em 20/10 com a captura `EditarSumario`, também com
/// um tipo próprio no lugar do `UUID`). Por isso as linhas são botões com a seta desenhada, e não `NavigationLink`.
struct EditarSumarioView: View {
    @StateObject private var viewModel: EditarSumarioViewModel
    @Environment(\.dismiss) private var dismiss
    /// O item aberto na tela de item (no máximo um: ela troca de item sem navegar).
    @State private var itemEmEdicao: UUID?

    init(viewModel: @autoclosure @escaping () -> EditarSumarioViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        NavigationStack {
            conteudo
                .navigationTitle("Sumário")
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
                .navigationDestination(isPresented: editandoItem) {
                    if let id = itemEmEdicao {
                        EdicaoDoItemView(viewModel: viewModel, itemId: id)
                    }
                }
        }
        .interactiveDismissDisabled(viewModel.alterado)
        .task { await viewModel.carregar() }
        .alertaDeErro($viewModel.mensagemDeErro)
    }

    @ViewBuilder
    private var conteudo: some View {
        switch viewModel.estado {
        case .carregando:
            ProgressView()
        case .naoEncontrado:
            Text("Livro não encontrado")
                .foregroundColor(Cor.textoSecundario)
        case .pronto:
            lista
        case .erro(let texto):
            MensagemDeErroView(texto: texto) {
                Task { await viewModel.carregar() }
            }
        }
    }

    private var lista: some View {
        List {
            if viewModel.quantidadeDeItensComErro > 0 {
                Section {
                    Text(textoDosErros)
                        .foregroundColor(Cor.perigo)
                }
            }
            Section {
                ForEach(viewModel.itens) { item in
                    Button {
                        itemEmEdicao = item.id
                    } label: {
                        HStack(spacing: Espaco.pequeno) {
                            linha(item)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(Color(.tertiaryLabel))
                                .accessibilityHidden(true)
                        }
                        // O botão pintaria o texto com o destaque; aqui o item é conteúdo, não ação.
                        .foregroundColor(.primary)
                    }
                    .swipeActions(edge: .leading) { botoesDeNivel(item) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.apagar(id: item.id)
                        } label: {
                            Label("Apagar", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button {
                            itemEmEdicao = viewModel.inserir(abaixoDe: item.id)
                        } label: {
                            Label("Inserir abaixo", systemImage: "text.insert")
                        }
                        Button(role: .destructive) {
                            viewModel.apagar(id: item.id)
                        } label: {
                            Label("Apagar", systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: viewModel.mover)
            } footer: {
                if viewModel.itens.isEmpty {
                    Text("Nenhum item ainda. Escreva o sumário item a item, na ordem impressa.")
                }
            }
            Section {
                Button {
                    itemEmEdicao = viewModel.adicionarNoFim()
                } label: {
                    Label("Adicionar item", systemImage: "plus")
                }
            }
        }
    }

    /// O item e, embaixo, o erro (só depois de tentar salvar) ou o aviso de página (sempre).
    private func linha(_ item: RascunhoSumario.Item) -> some View {
        VStack(alignment: .leading, spacing: Espaco.minimo) {
            ItemDoSumarioView(item)
            if let erro = viewModel.erro(doItem: item.id) {
                Text(erro)
                    .font(.footnote)
                    .foregroundColor(Cor.perigo)
            } else if let aviso = viewModel.aviso(doItem: item.id) {
                Label(aviso, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundColor(Cor.textoSecundario)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Só os botões que mudam algo: sem "Diminuir" no nível 1, sem "Aumentar" no limite.
    @ViewBuilder
    private func botoesDeNivel(_ item: RascunhoSumario.Item) -> some View {
        if item.nivel > 1 {
            Button {
                viewModel.diminuirNivel(id: item.id)
            } label: {
                Label("Diminuir nível", systemImage: "decrease.indent")
            }
            .tint(Cor.textoSecundario)
        }
        if item.nivel < viewModel.nivelMaximo(id: item.id) {
            Button {
                viewModel.aumentarNivel(id: item.id)
            } label: {
                Label("Aumentar nível", systemImage: "increase.indent")
            }
            .tint(Cor.destaque)
        }
    }

    private var editandoItem: Binding<Bool> {
        Binding(get: { itemEmEdicao != nil }, set: { if !$0 { itemEmEdicao = nil } })
    }

    private var textoDosErros: String {
        let quantidade = viewModel.quantidadeDeItensComErro
        return quantidade == 1
            ? "1 item com erro. Corrija-o para salvar."
            : "\(quantidade) itens com erro. Corrija-os para salvar."
    }
}

