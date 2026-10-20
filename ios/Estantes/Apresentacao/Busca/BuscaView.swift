import SwiftUI

/// A tela "Busca", empurrada pelo botão do Inicio: campo próprio no topo, chips, resultados, e de dentro dela
/// o Detalhe e a tela Filtros. Na volta deles, a busca está como ficou.
///
/// Campo próprio, e não `.searchable`: no iOS 16, empurrar uma tela desliga o `.searchable` e ele volta inativo,
/// sem o "Cancelar" (visto no log; ver Histórico de 20/10). Aqui o "Cancelar" é um botão da barra, sempre à vista.
/// O `BuscaViewModel` nasce a cada entrada: cancelar descarta a busca, e a próxima começa do zero.
struct BuscaView: View {
    /// O texto do campo e do botão do Inicio (um parece o outro).
    static let textoDoCampo = "Título, autor ou assunto"
    /// No iOS 16, o foco (e o `isPresented` da navegação) dado antes de a tela terminar de entrar se perde.
    private static let esperaDaEntrada: UInt64 = 400_000_000

    /// O que fazer ao entrar. Fora o padrão, só as capturas usam (sem teclado na frente; Filtros ou Categorias
    /// já abertas), como a `AcaoInicial` do Inicio e de Categorias.
    enum AcaoInicial {
        case focarNoCampo
        case nenhuma
        case abrirFiltros
        case abrirCategorias
    }

    @StateObject private var busca: BuscaViewModel
    private let miniaturas: CarregadorDeMiniaturas
    private let acaoInicial: AcaoInicial

    @State private var mostrandoFiltros = false
    @State private var mostrandoCategorias = false
    /// A ação inicial só vale na primeira vez: na volta de Filtros ou do Detalhe, o teclado cobriria a lista.
    @State private var jaApareceu = false
    @FocusState private var campoFocado: Bool
    @Environment(\.dismiss) private var voltar

    init(
        viewModel: @autoclosure @escaping () -> BuscaViewModel,
        miniaturas: CarregadorDeMiniaturas,
        acaoInicial: AcaoInicial = .focarNoCampo
    ) {
        _busca = StateObject(wrappedValue: viewModel())
        self.miniaturas = miniaturas
        self.acaoInicial = acaoInicial
    }

    var body: some View {
        ResultadosDaBuscaView(
            busca: busca, miniaturas: miniaturas,
            abrirFiltros: { mostrandoFiltros = true }, abrirCategorias: { mostrandoCategorias = true }
        ) {
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
        .navigationDestination(isPresented: $mostrandoCategorias) {
            CategoriasDaBuscaView(busca: busca)
        }
        .task {
            guard !jaApareceu else { return }
            // Cancelada (a tela saiu durante a espera, por "Cancelar"): nada muda numa tela que já não está aí, e
            // `jaApareceu` fica falso para a ação valer se ela voltar.
            do { try await Task.sleep(nanoseconds: BuscaView.esperaDaEntrada) } catch { return }
            jaApareceu = true
            switch acaoInicial {
            case .focarNoCampo: campoFocado = true
            case .nenhuma: break
            case .abrirFiltros: mostrandoFiltros = true
            case .abrirCategorias: mostrandoCategorias = true
            }
        }
    }

    /// Lupa, texto e o ✕ que limpa (só com texto), no desenho da barra de busca do sistema.
    private var campo: some View {
        HStack(spacing: Espaco.pequeno) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Cor.textoSecundario)
                .accessibilityHidden(true)
            TextField(BuscaView.textoDoCampo, text: $busca.texto)
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
        .campoDeBusca()
    }
}

private extension View {
    /// A cápsula do campo de busca, igual no campo da "Busca" e no botão do Inicio (um parece o outro).
    func campoDeBusca() -> some View {
        padding(.horizontal, Espaco.medio)
            .padding(.vertical, Espaco.pequeno)
            .background(Cor.campo)
            .cantos(Raio.medio)
    }
}

/// O botão do Inicio que abre a "Busca": tem a aparência da barra de busca, para ser achado sem explicação.
struct BotaoDeBusca: View {
    var body: some View {
        NavigationLink(value: RotaDaBusca()) {
            HStack(spacing: Espaco.pequeno) {
                Image(systemName: "magnifyingglass")
                Text(BuscaView.textoDoCampo)
                Spacer(minLength: 0)
            }
            .foregroundColor(Cor.textoSecundario)
            .campoDeBusca()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Buscar por título, autor ou assunto")
    }
}
