import SwiftUI

/// Tela de um item do sumário, empurrada dentro da folha "Editar sumário" ("Adicionar item", tocar num item ou
/// "Inserir abaixo"). Os campos escrevem direto no rascunho da folha: voltar não perde nada, e o "Cancelar" da folha
/// ainda descarta tudo.
///
/// "Próximo item" cria um item vazio logo abaixo, no mesmo nível, e troca esta tela para ele **sem navegar**: o
/// teclado fica aberto no Título, para digitar um sumário em sequência. O Return anda pelos campos (Numeração →
/// Título → Página) e, na Página, faz o "Próximo item".
struct EdicaoDoItemView: View {
    @ObservedObject var viewModel: EditarSumarioViewModel
    @State private var itemId: UUID
    @FocusState private var campoEmFoco: Campo?

    private enum Campo {
        case numeracao, titulo, pagina
    }

    init(viewModel: EditarSumarioViewModel, itemId: UUID) {
        self.viewModel = viewModel
        _itemId = State(initialValue: itemId)
    }

    var body: some View {
        Group {
            if let item = viewModel.item(id: itemId) {
                formulario(item)
            } else {
                Text("Item não encontrado")
                    .foregroundColor(Cor.textoSecundario)
            }
        }
        .navigationTitle("Item do sumário")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // No iOS 16, o foco pedido logo ao aparecer se perde durante o empurrão; espera a transição acabar.
            try? await Task.sleep(nanoseconds: 500_000_000)
            campoEmFoco = .titulo
        }
        .onDisappear { viewModel.descartarSeVazio(id: itemId) }
    }

    private func formulario(_ item: RascunhoSumario.Item) -> some View {
        Form {
            Section {
                TextField("Numeração", text: texto(\.numeracao), prompt: Text("Numeração (ex.: Capítulo II, § 5.108)"))
                    .focused($campoEmFoco, equals: .numeracao)
                    .submitLabel(.next)
                    .onSubmit { campoEmFoco = .titulo }
                titulo
                TextField("Página", text: texto(\.pagina), prompt: Text("Página (ex.: 45, XI)"))
                    .keyboardType(.numbersAndPunctuation)
                    .focused($campoEmFoco, equals: .pagina)
                    .submitLabel(.next)
                    .onSubmit(proximoItem)
            } footer: {
                problemas
            }
            Section {
                Stepper("Nível \(item.nivel)", value: nivel, in: 1...max(viewModel.nivelMaximo(id: itemId), item.nivel))
            } footer: {
                Text("O nível vai de 1 até um a mais que o do item de cima.")
            }
            Section {
                Button("Próximo item", action: proximoItem)
                    .disabled(Normalizacao.textoLimpo(item.titulo) == nil)
            }
        }
    }

    /// Títulos jurídicos são longos: o campo cresce para baixo. O Return não quebra a linha, passa para a Página.
    private var titulo: some View {
        let texto = texto(\.titulo)
        return TextField("Título", text: texto, prompt: Text("Título"), axis: .vertical)
            .focused($campoEmFoco, equals: .titulo)
            .onChange(of: texto.wrappedValue) { novo in
                guard novo.contains(where: \.isNewline) else { return }
                texto.wrappedValue = novo.split(whereSeparator: \.isNewline).joined(separator: " ")
                campoEmFoco = .pagina
            }
    }

    @ViewBuilder
    private var problemas: some View {
        if let erro = viewModel.erro(doItem: itemId) {
            Text(erro).foregroundColor(Cor.perigo)
        } else if let aviso = viewModel.aviso(doItem: itemId) {
            Label(aviso, systemImage: "exclamationmark.triangle")
                .foregroundColor(Cor.textoSecundario)
        }
    }

    private func proximoItem() {
        guard let item = viewModel.item(id: itemId), Normalizacao.textoLimpo(item.titulo) != nil,
              let novo = viewModel.proximoItem(depoisDe: itemId) else { return }
        itemId = novo
        campoEmFoco = .titulo
    }

    private func texto(_ campo: WritableKeyPath<RascunhoSumario.Item, String>) -> Binding<String> {
        Binding(
            get: { viewModel.item(id: itemId)?[keyPath: campo] ?? "" },
            set: { novo in
                guard var item = viewModel.item(id: itemId) else { return }
                item[keyPath: campo] = novo
                viewModel.atualizar(item)
            }
        )
    }

    private var nivel: Binding<Int> {
        Binding(
            get: { viewModel.item(id: itemId)?.nivel ?? 1 },
            set: { novo in
                guard var item = viewModel.item(id: itemId) else { return }
                item.nivel = novo
                viewModel.atualizar(item)
            }
        )
    }
}
