import SwiftUI

/// A pilha de navegação do app. Mora na montagem (`App/`) porque é aqui que cada valor empurrado
/// vira uma tela com o seu ViewModel: as telas só oferecem links (`Estante`, `RotaDoLivro`) e não
/// precisam conhecer `Dependencias`.
@MainActor
struct NavegacaoView: View {
    let dependencias: Dependencias
    private let acaoInicial: InicioView.AcaoInicial?
    private let acaoNasCategorias: CategoriasView.AcaoInicial?
    /// Em `@State` para sobreviver quando quem monta esta view a recria (o pedido já usado não volta).
    @State private var folhaPendente: FolhaPendente?
    @State private var caminho: NavigationPath

    /// Os parâmetros além de `dependencias` só servem às capturas do simulador (abrir já numa tela ou folha).
    init(
        dependencias: Dependencias,
        acaoInicial: InicioView.AcaoInicial? = nil,
        acaoNasCategorias: CategoriasView.AcaoInicial? = nil,
        caminhoInicial: NavigationPath = NavigationPath(),
        folhaInicial: FolhaPendente? = nil
    ) {
        self.dependencias = dependencias
        self.acaoInicial = acaoInicial
        self.acaoNasCategorias = acaoNasCategorias
        _folhaPendente = State(initialValue: folhaInicial)
        _caminho = State(initialValue: caminhoInicial)
    }

    var body: some View {
        NavigationStack(path: $caminho) {
            InicioView(
                viewModel: dependencias.fazerInicioViewModel(),
                busca: dependencias.fazerBuscaViewModel(),
                miniaturas: dependencias.miniaturas,
                abrirCategorias: { caminho.append(RotaDasCategorias()) },
                acaoInicial: acaoInicial
            )
                .navigationDestination(for: RotaDasCategorias.self) { _ in
                    CategoriasView(
                        viewModel: dependencias.fazerCategoriasViewModel(),
                        formulario: dependencias.fazerCategoriaFormularioViewModel,
                        acaoInicial: acaoNasCategorias
                    )
                }
                .navigationDestination(for: Estante.self) { estante in
                    EstanteView(
                        viewModel: dependencias.fazerEstanteViewModel(estante: estante),
                        miniaturas: dependencias.miniaturas,
                        formulario: dependencias.fazerLivroFormularioViewModel,
                        escolha: dependencias.fazerEscolhaDeCategoriasViewModel,
                        formularioDeCategoria: dependencias.fazerCategoriaFormularioViewModel,
                        abrirFormulario: folhaPendente?.folha(em: estante) == .formulario
                    )
                    .onAppear { folhaPendente?.esquecer(se: estante) }
                }
                .navigationDestination(for: RotaDoLivro.self) { rota in
                    let folha = folhaPendente?.folha(em: rota)
                    LivroDetalheView(
                        viewModel: dependencias.fazerLivroDetalheViewModel(livroId: rota.livroId),
                        miniaturas: dependencias.miniaturas,
                        formulario: dependencias.fazerLivroFormularioViewModel,
                        escolha: dependencias.fazerEscolhaDeCategoriasViewModel,
                        formularioDeCategoria: dependencias.fazerCategoriaFormularioViewModel,
                        edicaoDoSumario: dependencias.fazerEditarSumarioViewModel,
                        abrirConfirmacao: folha == .confirmacaoDeApagar,
                        abrirFormulario: folha == .formulario,
                        abrirCategorias: folha == .categorias,
                        abrirSumario: folha == .sumario
                    )
                    .onAppear { folhaPendente?.esquecer(se: rota) }
                }
        }
        // O índice da busca começa a ser montado ao abrir o app, sem prender a tela. A falha é ignorada
        // aqui de propósito: a primeira busca tenta de novo e aí mostra o erro.
        .task { try? await dependencias.biblioteca.preparar() }
    }
}

/// Folha que uma captura pede para abrir logo de início, numa tela só e uma vez só.
///
/// Classe (referência) porque precisa "esquecer" o pedido depois de usado, de dentro do `body` da
/// `NavegacaoView`, que é uma struct. Sem isso, toda tela criada depois (outro livro aberto, a mesma
/// estante revisitada) abriria a folha sozinha.
///
/// Ler (`folha(em:)`) e esquecer (`esquecer(se:)`) são passos separados: o SwiftUI pode chamar o bloco do
/// `navigationDestination` mais de uma vez e descartar a primeira tela montada. Esquecer ao montar gastaria
/// o pedido nessa tela descartada; o `onAppear` só roda na tela que ficou.
final class FolhaPendente {
    enum Folha {
        case formulario
        case confirmacaoDeApagar
        case categorias
        case sumario
    }

    private var pedido: (folha: Folha, alvo: AnyHashable)?

    /// - Parameter alvo: o valor empurrado na pilha cuja tela abre a folha (`Estante` ou `RotaDoLivro`).
    init(_ folha: Folha, em alvo: AnyHashable) {
        pedido = (folha, alvo)
    }

    /// A folha, se `valor` é a tela pedida.
    func folha(em valor: AnyHashable) -> Folha? {
        guard let pedido = pedido, pedido.alvo == valor else { return nil }
        return pedido.folha
    }

    /// Chamado quando a tela aparece: se é a tela pedida, as próximas já abrem normais.
    func esquecer(se valor: AnyHashable) {
        if pedido?.alvo == valor { pedido = nil }
    }
}
