import SwiftUI

/// A tela "Busca", empurrada pelo botão do Inicio: campo próprio no topo, chips, resultados, e de dentro dela
/// o Detalhe e a tela Filtros. Na volta deles, a busca está como ficou.
///
/// Campo próprio, e não `.searchable`: no iOS 16, empurrar uma tela desliga o `.searchable` e ele volta inativo,
/// sem o "Cancelar" (visto no log; ver Histórico de 20/10). Aqui o "Cancelar" é um botão da barra, sempre à vista.
/// O `BuscaViewModel` nasce a cada entrada: cancelar descarta a busca, e a próxima começa do zero.
struct BuscaView: View {
    @StateObject private var busca: BuscaViewModel
    private let miniaturas: CarregadorDeMiniaturas
    private let focarAoAbrir: Bool
    private let abrirFiltrosAoAbrir: Bool

    @State private var mostrandoFiltros = false
    /// O foco só vai sozinho ao campo na primeira vez: na volta de Filtros ou do Detalhe, o teclado cobriria a lista.
    @State private var jaApareceu = false
    @FocusState private var campoFocado: Bool
    @Environment(\.dismiss) private var voltar

    /// `focarAoAbrir` e `abrirFiltrosAoAbrir` só servem às capturas (sem teclado na frente; Filtros já aberta).
    init(
        viewModel: @autoclosure @escaping () -> BuscaViewModel,
        miniaturas: CarregadorDeMiniaturas,
        focarAoAbrir: Bool = true,
        abrirFiltrosAoAbrir: Bool = false
    ) {
        _busca = StateObject(wrappedValue: viewModel())
        self.miniaturas = miniaturas
        self.focarAoAbrir = focarAoAbrir
        self.abrirFiltrosAoAbrir = abrirFiltrosAoAbrir
    }

    var body: some View {
        ResultadosDaBuscaView(busca: busca, miniaturas: miniaturas, abrirFiltros: { mostrandoFiltros = true }) {
            campo
        }
        .navigationTitle("Busca")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Cancelar") { voltar() }
            }
        }
        .navigationDestination(isPresented: $mostrandoFiltros) {
            FiltrosDaBuscaView(busca: busca)
        }
        .task {
            guard !jaApareceu else { return }
            jaApareceu = true
            // No iOS 16, o foco (e o `isPresented` da navegação) dado antes de a tela terminar de entrar se perde.
            try? await Task.sleep(nanoseconds: 400_000_000)
            if focarAoAbrir { campoFocado = true }
            if abrirFiltrosAoAbrir { mostrandoFiltros = true }
        }
    }

    /// Lupa, texto e o ✕ que limpa (só com texto), no desenho da barra de busca do sistema.
    private var campo: some View {
        HStack(spacing: Espaco.pequeno) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Cor.textoSecundario)
                .accessibilityHidden(true)
            TextField("Título, autor ou assunto", text: $busca.texto)
                .focused($campoFocado)
                .submitLabel(.search)
                .onSubmit { campoFocado = false }
                .autocorrectionDisabled()
            if !busca.texto.isEmpty {
                Button {
                    busca.texto = ""
                    campoFocado = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Cor.textoSecundario)
                }
                .accessibilityLabel("Limpar o texto")
            }
        }
        .padding(.horizontal, Espaco.medio)
        .padding(.vertical, Espaco.pequeno)
        .background(Color(uiColor: .tertiarySystemFill))
        .cantos(Raio.medio)
    }
}

/// O botão do Inicio que abre a "Busca": tem a aparência da barra de busca, para ser achado sem explicação.
struct BotaoDeBusca: View {
    var body: some View {
        NavigationLink(value: RotaDaBusca()) {
            HStack(spacing: Espaco.pequeno) {
                Image(systemName: "magnifyingglass")
                Text("Título, autor ou assunto")
                Spacer(minLength: 0)
            }
            .foregroundColor(Cor.textoSecundario)
            .padding(.horizontal, Espaco.medio)
            .padding(.vertical, Espaco.pequeno)
            .background(Color(uiColor: .tertiarySystemFill))
            .cantos(Raio.medio)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Buscar por título, autor ou assunto")
    }
}
