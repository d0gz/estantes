import SwiftUI

/// Mensagem de erro de tela inteira, com "Tentar de novo" opcional.
struct MensagemDeErroView: View {
    let texto: String
    var tentarDeNovo: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(texto)
                .multilineTextAlignment(.center)
            if let tentarDeNovo = tentarDeNovo {
                Button("Tentar de novo", action: tentarDeNovo)
            }
        }
        .padding()
    }
}

struct MensagemDeErroView_Previews: PreviewProvider {
    static var previews: some View {
        MensagemDeErroView(texto: "Não foi possível carregar as estantes.", tentarDeNovo: {})
    }
}
