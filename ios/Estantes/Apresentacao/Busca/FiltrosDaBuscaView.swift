import SwiftUI

/// A tela "Filtros" da busca: os filtros que pedem texto (autor, editora, anos). Ligada direto ao
/// filtro da busca, então a lista já está atualizada na volta.
/// Empurrada, e não em folha: no iOS 16, tocar num campo de uma folha tirava o foco da busca e, ao fechar,
/// o Inicio voltava às estantes; empurrar (como o Detalhe) mantém a busca ativa.
/// Estantes e categorias ficam na barra de chips, e a CDDir fica fora até haver livros com ela.
struct FiltrosDaBuscaView: View {
    @ObservedObject var busca: BuscaViewModel
    /// O texto dos anos como foi digitado: "197" fica no campo, mas só um ano completo vai para o filtro.
    @State private var anoInicial: String
    @State private var anoFinal: String

    init(busca: BuscaViewModel) {
        self.busca = busca
        _anoInicial = State(initialValue: busca.filtro.anoMinimo.map(String.init) ?? "")
        _anoFinal = State(initialValue: busca.filtro.anoMaximo.map(String.init) ?? "")
    }

    var body: some View {
        Form {
            Section("Autor") {
                TextField("Ex.: Pontes de Miranda", text: texto(\.autor))
                    .textInputAutocapitalization(.words)
            }
            Section("Editora") {
                TextField("Ex.: Saraiva", text: texto(\.editora))
                    .textInputAutocapitalization(.words)
            }
            Section {
                TextField("De (ex.: 1950)", text: $anoInicial)
                    .keyboardType(.numberPad)
                TextField("Até (ex.: 1980)", text: $anoFinal)
                    .keyboardType(.numberPad)
            } header: {
                Text("Ano de publicação")
            } footer: {
                if busca.faixaDeAnosInvertida {
                    VStack(alignment: .leading, spacing: Espaco.minimo) {
                        Text("O ano inicial é depois do final.")
                            .foregroundColor(Cor.perigo)
                        Text("Corrija os anos ou limpe os filtros para voltar.")
                    }
                } else {
                    Text("Só \"De\": desse ano em diante. Só \"Até\": até esse ano. Os dois anos entram no intervalo.")
                }
            }
            Section {
                Button("Limpar estes filtros", role: .destructive) {
                    busca.filtro.autor = nil
                    busca.filtro.editora = nil
                    anoInicial = ""
                    anoFinal = ""
                }
            }
        }
        .navigationTitle("Filtros")
        .navigationBarTitleDisplayMode(.inline)
        // Faixa invertida não acha nenhum livro: não dá para voltar com ela. Sem o botão, o iOS 16 também
        // desliga o gesto de voltar pela borda.
        .navigationBarBackButtonHidden(busca.faixaDeAnosInvertida)
        // `onChange` de um parâmetro: deprecated no iOS 17, mas é a forma que o Xcode 14.2 aceita.
        .onChange(of: anoInicial) { busca.filtro.anoMinimo = BuscaViewModel.ano(deTexto: $0) }
        .onChange(of: anoFinal) { busca.filtro.anoMaximo = BuscaViewModel.ano(deTexto: $0) }
    }

    /// Campo vazio = sem filtro (`nil`); o `FiltroBusca` também ignora texto só com espaços.
    private func texto(_ campo: WritableKeyPath<FiltroBusca, String?>) -> Binding<String> {
        Binding(
            get: { busca.filtro[keyPath: campo] ?? "" },
            set: { busca.filtro[keyPath: campo] = $0.isEmpty ? nil : $0 }
        )
    }
}
