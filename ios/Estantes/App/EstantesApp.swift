import SwiftUI

/// Ponto de entrada do app: monta as dependências (`Dependencias`) e abre a tela inicial.
/// Sem `.environment(\.managedObjectContext)` nem `@FetchRequest`: os ViewModels recebem o repositório pelo init.
@main
struct EstantesApp: App {
    /// `Result` em vez de `try!`: se o banco não abrir, o app mostra o erro em vez de fechar sozinho.
    private let montagem = Result { try Dependencias.producao() }

    var body: some Scene {
        WindowGroup {
            RaizView(montagem: montagem)
        }
    }
}

/// `@MainActor` no tipo: no SDK do Xcode 14 só o `body` é isolado na fila principal, não as propriedades auxiliares.
@MainActor
private struct RaizView: View {
    let montagem: Result<Dependencias, Error>

    var body: some View {
        #if DEBUG
        if let captura = Captura.pedida {
            captura.tela
        } else {
            telaDoApp
        }
        #else
        telaDoApp
        #endif
    }

    @ViewBuilder
    private var telaDoApp: some View {
        switch montagem {
        case .success(let dependencias):
            InicioView(viewModel: dependencias.fazerInicioViewModel())
        case .failure:
            MensagemDeErroView(texto: "Não foi possível abrir a biblioteca guardada no aparelho.")
        }
    }
}
