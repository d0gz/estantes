import Foundation

/// Exportar e importar a biblioteca (menu ⋯ do Inicio) e, nos builds com exemplos, carregar os dados de exemplo.
@MainActor
final class ExportacaoViewModel: ObservableObject {
    /// O arquivo gerado, pronto para a folha de compartilhar. `Identifiable` para abrir a folha com `.sheet(item:)`.
    struct ArquivoExportado: Identifiable, Equatable {
        let url: URL
        var id: URL { url }
    }

    /// Arquivo lido e validado, esperando a escolha entre mesclar e substituir.
    ///
    /// Cada leitura é única (`id`), e a igualdade compara só o `id`: ler o mesmo arquivo de novo (depois de fechar
    /// o diálogo tocando fora) é uma mudança que a tela percebe, e a comparação não percorre a biblioteca inteira.
    struct ImportacaoPendente: Equatable {
        let id = UUID()
        let conteudo: ConteudoDaBiblioteca
        /// "10 livros · 3 estantes · 5 categorias".
        let resumo: String

        static func == (a: ImportacaoPendente, b: ImportacaoPendente) -> Bool { a.id == b.id }
    }

    /// Resultado ou erro, num alerta.
    struct Aviso: Identifiable, Equatable {
        let titulo: String
        let mensagem: String
        var id: String { titulo + mensagem }
    }

    @Published var arquivoExportado: ArquivoExportado?
    @Published var importacaoPendente: ImportacaoPendente?
    @Published var aviso: Aviso?

    private let exportar: ExportarBiblioteca
    private let importar: ImportarBiblioteca
    /// Só existe nos builds com exemplos (`DEBUG || EXEMPLOS`): quem decide é a montagem, não a tela.
    private let acaoDosExemplos: (() async throws -> Void)?
    private let hoje: () -> Date
    private let pasta: URL

    init(
        exportar: ExportarBiblioteca,
        importar: ImportarBiblioteca,
        carregarExemplos: (() async throws -> Void)? = nil,
        hoje: @escaping () -> Date = Date.init,
        pasta: URL = FileManager.default.temporaryDirectory
    ) {
        self.exportar = exportar
        self.importar = importar
        acaoDosExemplos = carregarExemplos
        self.hoje = hoje
        self.pasta = pasta
    }

    var podeCarregarExemplos: Bool { acaoDosExemplos != nil }

    // MARK: Exportar

    /// Gera o arquivo numa pasta temporária e abre a folha de compartilhar (Salvar em Arquivos, AirDrop…).
    func exportarBiblioteca() async {
        do {
            let dados = try await exportar.executar()
            apagarExportacoesAnteriores()
            let url = pasta.appendingPathComponent("Estantes-\(Self.formatoDoNome.string(from: hoje())).json")
            try dados.write(to: url, options: .atomic)
            arquivoExportado = ArquivoExportado(url: url)
        } catch {
            aviso = Aviso(titulo: "Exportação não concluída", mensagem: "Não foi possível gerar o arquivo da biblioteca.")
        }
    }

    /// A pasta temporária só é limpa pelo sistema de vez em quando: sem isto, cada dia exportado deixaria uma
    /// cópia da biblioteca lá. Só os arquivos com o nome da exportação; falhar aqui não impede exportar.
    private func apagarExportacoesAnteriores() {
        let arquivos = (try? FileManager.default.contentsOfDirectory(at: pasta, includingPropertiesForKeys: nil)) ?? []
        for arquivo in arquivos where arquivo.lastPathComponent.hasPrefix("Estantes-") && arquivo.pathExtension == "json" {
            try? FileManager.default.removeItem(at: arquivo)
        }
    }

    // MARK: Importar

    /// Lê e valida o arquivo escolhido; se der certo, a tela pergunta entre mesclar e substituir.
    /// Nada é gravado aqui.
    func lerArquivo(_ url: URL) {
        // O arquivo vem do seletor (fora da área do app): o acesso precisa ser pedido e devolvido.
        let comAcesso = url.startAccessingSecurityScopedResource()
        defer { if comAcesso { url.stopAccessingSecurityScopedResource() } }
        do {
            let conteudo = try importar.ler(Data(contentsOf: url))
            let resumo = [
                Quantidade.livros(conteudo.livros.count),
                Quantidade.estantes(conteudo.estantes.count),
                Quantidade.categorias(conteudo.categorias.count),
            ].joined(separator: " · ")
            importacaoPendente = ImportacaoPendente(conteudo: conteudo, resumo: resumo)
        } catch ErroDeImportacao.versaoMaisNova {
            aviso = Aviso(titulo: "Arquivo de uma versão mais nova",
                          mensagem: "Este backup foi feito por uma versão mais nova do Estantes. Atualize o app para importá-lo.")
        } catch {
            aviso = Aviso(titulo: "Arquivo inválido",
                          mensagem: "Este arquivo não é um backup do Estantes, ou foi alterado fora do app.")
        }
    }

    /// - Returns: se a biblioteca mudou (a tela então relê as estantes do Inicio).
    @discardableResult
    func confirmarImportacao(_ modo: ImportarBiblioteca.Modo) async -> Bool {
        guard let pendente = importacaoPendente else { return false }
        importacaoPendente = nil
        do {
            try await importar.importar(pendente.conteudo, modo: modo)
        } catch {
            // A gravação é atômica: se falhou, a biblioteca ficou como estava e não há o que recarregar.
            aviso = Aviso(titulo: "Importação não concluída", mensagem: "Nada foi alterado na biblioteca.")
            return false
        }
        let mensagem = modo == .mesclar
            ? "O conteúdo do arquivo foi juntado à biblioteca (\(pendente.resumo))."
            : "A biblioteca agora é a do arquivo (\(pendente.resumo))."
        aviso = Aviso(titulo: "Biblioteca importada", mensagem: mensagem)
        return true
    }

    /// O seletor de arquivos não conseguiu entregar o arquivo escolhido.
    func arquivoNaoAberto() {
        aviso = Aviso(titulo: "Arquivo não aberto", mensagem: "Não foi possível abrir o arquivo escolhido.")
    }

    func cancelarImportacao() {
        importacaoPendente = nil
    }

    // MARK: Exemplos

    /// - Returns: se a biblioteca mudou.
    @discardableResult
    func carregarExemplos() async -> Bool {
        guard let acaoDosExemplos = acaoDosExemplos else { return false }
        do {
            try await acaoDosExemplos()
            return true
        } catch {
            aviso = Aviso(titulo: "Exemplos não carregados", mensagem: "Nada foi alterado na biblioteca.")
            return false
        }
    }

    /// Dia local no nome do arquivo ("Estantes-2026-10-21.json"); `en_US_POSIX` para o formato não variar
    /// com as preferências do aparelho.
    private static let formatoDoNome: DateFormatter = {
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "en_US_POSIX")
        formato.dateFormat = "yyyy-MM-dd"
        return formato
    }()
}
