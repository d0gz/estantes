import SwiftUI

/// Ponto de entrada do app.
/// Fase 2: `App/Dependencias` monta PersistenceController → BibliotecaRepositorioCoreData → ViewModels,
/// injetados pelo init (sem `.environment(\.managedObjectContext)` nem `@FetchRequest`; ver docs/PLANO.md).
@main
struct EstantesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
