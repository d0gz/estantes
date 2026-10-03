import Foundation

/// Informações do app lidas do Info.plist.
/// Fica em App/ e não no Dominio/: ler o bundle é detalhe de montagem do app, não regra de negócio.
enum AppInfo {
    static var versao: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
