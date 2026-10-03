import SwiftUI

/// Tela provisória da Fase 0: só confirma que o projeto compila no Xcode 14.2 e no Xcode 26.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 56))
                    .foregroundColor(.accentColor)
                Text("Estantes")
                    .font(.largeTitle.bold())
            }
            .navigationTitle("Minhas estantes")
        }
    }
}

// PreviewProvider em vez de #Preview: a macro #Preview só existe a partir do Xcode 15.
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
