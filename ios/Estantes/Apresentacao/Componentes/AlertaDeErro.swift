import SwiftUI

extension View {
    /// Alerta "Algo deu errado" com a mensagem do ViewModel; o "OK" limpa a mensagem e fecha o alerta.
    func alertaDeErro(_ mensagem: Binding<String?>) -> some View {
        alert("Algo deu errado", isPresented: Binding(
            get: { mensagem.wrappedValue != nil },
            set: { if !$0 { mensagem.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mensagem.wrappedValue ?? "")
        }
    }
}
