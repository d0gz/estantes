import SwiftUI
import UIKit

/// A folha de compartilhar do sistema (Salvar em Arquivos, AirDrop, Mail…) para um arquivo já gravado.
///
/// UIKit, e não `ShareLink`: o `ShareLink` precisa do arquivo pronto antes do toque e não pode ser aberto
/// por código; aqui o arquivo é gerado no toque e a folha abre depois (decidido em 21/10, T2).
struct FolhaDeCompartilhar: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controlador: UIActivityViewController, context: Context) {}
}
