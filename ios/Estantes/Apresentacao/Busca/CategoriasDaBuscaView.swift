import SwiftUI

/// A tela "Categorias" da busca: marcar várias de uma vez (vale "qualquer destas", como nas estantes). Empurrada,
/// como a tela Filtros, para a busca continuar como ficou na volta; a lista atrás já reage a cada toque.
struct CategoriasDaBuscaView: View {
    @ObservedObject var busca: BuscaViewModel

    var body: some View {
        List {
            Section {
                ForEach(busca.categorias) { categoria in
                    let marcada = busca.filtro.categoriaIds.contains(categoria.id)
                    Button {
                        busca.alternar(categoria: categoria.id)
                    } label: {
                        HStack(spacing: Espaco.medio) {
                            ChipDeCategoria(categoria)
                            Spacer(minLength: 0)
                            if marcada {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(Cor.destaque)
                            }
                        }
                    }
                    .accessibilityAddTraits(marcada ? .isSelected : [])
                }
            } footer: {
                Text("Mostra os livros com qualquer uma das categorias marcadas.")
            }
            if !busca.filtro.categoriaIds.isEmpty {
                Section {
                    Button("Desmarcar todas", role: .destructive) {
                        busca.filtro.categoriaIds = []
                    }
                }
            }
        }
        .navigationTitle("Categorias")
        .navigationBarTitleDisplayMode(.inline)
    }
}
