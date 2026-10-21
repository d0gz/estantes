import Foundation

/// Porta do arquivo de exportação: transforma a biblioteca em bytes e de volta.
///
/// Existe para que a Apresentação (que só enxerga o Domínio) possa ler o arquivo escolhido e mostrar o resumo
/// antes de importar, sem conhecer o formato. A camada Dados implementa (`BibliotecaExportadaV1`); um formato
/// v2 seria outra implementação, sem mexer no Domínio.
protocol CodificadorDeBiblioteca {
    func codificar(_ conteudo: ConteudoDaBiblioteca) throws -> Data
    /// Lança `ErroDeImportacao`. Não confere a coerência do conteúdo (é papel da `ValidacaoDaBiblioteca`).
    func decodificar(_ dados: Data) throws -> ConteudoDaBiblioteca
}

/// Por que um arquivo não pode ser importado. A tela distingue só os dois casos: o que o usuário pode
/// resolver (atualizar o app) e o resto.
enum ErroDeImportacao: Error, Equatable {
    /// O arquivo foi gerado por uma versão mais nova do app, com um formato que esta não conhece.
    case versaoMaisNova(Int)
    /// JSON quebrado, campo obrigatório ausente, valor desconhecido ou conteúdo incoerente.
    case arquivoInvalido
}
