import SwiftUI

/// A pilha de navegação do app. Mora na montagem (`App/`) porque é aqui que cada valor empurrado
/// vira uma tela com o seu ViewModel: as telas só oferecem links (`Estante`, `RotaDoLivro`) e não
/// precisam conhecer `Dependencias`.
@MainActor
struct NavegacaoView: View {
    let dependencias: Dependencias
    private let acaoInicial: InicioView.AcaoInicial?
    private let abrirConfirmacaoDoLivro: Bool
    private let abrirFormulario: Bool
    @State private var caminho: NavigationPath

    /// Os parâmetros além de `dependencias` só servem às capturas do simulador (abrir já numa tela ou folha).
    init(
        dependencias: Dependencias,
        acaoInicial: InicioView.AcaoInicial? = nil,
        caminhoInicial: NavigationPath = NavigationPath(),
        abrirConfirmacaoDoLivro: Bool = false,
        abrirFormulario: Bool = false
    ) {
        self.dependencias = dependencias
        self.acaoInicial = acaoInicial
        self.abrirConfirmacaoDoLivro = abrirConfirmacaoDoLivro
        self.abrirFormulario = abrirFormulario
        _caminho = State(initialValue: caminhoInicial)
    }

    var body: some View {
        NavigationStack(path: $caminho) {
            InicioView(viewModel: dependencias.fazerInicioViewModel(), acaoInicial: acaoInicial)
                .navigationDestination(for: Estante.self) { estante in
                    EstanteView(
                        viewModel: dependencias.fazerEstanteViewModel(estante: estante),
                        formulario: dependencias.fazerLivroFormularioViewModel,
                        // Só a tela do topo abre a folha: com a estante embaixo do livro, as duas tentariam.
                        abrirFormulario: abrirFormulario && caminho.count == 1
                    )
                }
                .navigationDestination(for: RotaDoLivro.self) { rota in
                    LivroDetalheView(
                        viewModel: dependencias.fazerLivroDetalheViewModel(livroId: rota.livroId),
                        formulario: dependencias.fazerLivroFormularioViewModel,
                        abrirConfirmacao: abrirConfirmacaoDoLivro,
                        abrirFormulario: abrirFormulario
                    )
                }
        }
    }
}
