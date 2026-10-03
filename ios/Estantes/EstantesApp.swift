import SwiftUI

/// Ponto de entrada do app.
/// Fase 2: aqui entra o PersistenceController (Core Data) via `.environment(\.managedObjectContext, ...)`.
@main
struct EstantesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
