import SwiftUI

/// A folha "Filtros" da busca: os filtros que pedem texto (autor, editora, anos). Ligada direto ao
/// filtro da busca, então a lista atrás já muda enquanto se digita; "OK" só fecha.
/// Estantes e categorias ficam nos chips da barra, e a CDDir fica fora até haver livros com ela.
struct FiltrosDaBuscaView: View {
    @Binding var filtro: FiltroBusca
    @Environment(\.dismiss) private var fechar

    var body: some View {
        NavigationStack {
            Form {
                Section("Autor") {
                    TextField("Ex.: Pontes de Miranda", text: texto(\.autor))
                        .textInputAutocapitalization(.words)
                }
                Section("Editora") {
                    TextField("Ex.: Saraiva", text: texto(\.editora))
                        .textInputAutocapitalization(.words)
                }
                Section("Ano de publicação") {
                    TextField("De", text: ano(\.anoMinimo))
                        .keyboardType(.numberPad)
                    TextField("Até", text: ano(\.anoMaximo))
                        .keyboardType(.numberPad)
                }
                Section {
                    Button("Limpar estes filtros", role: .destructive) {
                        filtro.autor = nil
                        filtro.editora = nil
                        filtro.anoMinimo = nil
                        filtro.anoMaximo = nil
                    }
                }
            }
            .navigationTitle("Filtros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { fechar() }
                }
            }
        }
    }

    /// Campo vazio = sem filtro (`nil`); o `FiltroBusca` também ignora texto só com espaços.
    private func texto(_ campo: WritableKeyPath<FiltroBusca, String?>) -> Binding<String> {
        Binding(
            get: { filtro[keyPath: campo] ?? "" },
            set: { filtro[keyPath: campo] = $0.isEmpty ? nil : $0 }
        )
    }

    /// Só os dígitos contam (texto colado com outra coisa não vira ano); vazio = sem filtro.
    private func ano(_ campo: WritableKeyPath<FiltroBusca, Int?>) -> Binding<String> {
        Binding(
            get: { filtro[keyPath: campo].map(String.init) ?? "" },
            set: { filtro[keyPath: campo] = Int($0.filter(\.isNumber)) }
        )
    }
}
