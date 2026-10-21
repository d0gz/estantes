import Foundation

/// Importa um arquivo de backup em dois tempos: `ler` (para a tela mostrar o resumo e perguntar) e
/// `importar` (depois da escolha entre mesclar e substituir).
struct ImportarBiblioteca {
    enum Modo {
        /// Junta com o que está no aparelho; o arquivo vence por UUID (`Mesclagem`).
        case mesclar
        /// A biblioteca fica igual ao arquivo; só as fotos dos livros que continuam ficam.
        case substituir
    }

    let repositorio: BibliotecaRepositorio
    let codificador: CodificadorDeBiblioteca

    /// Lança `ErroDeImportacao`. Um arquivo bem formado mas incoerente (`ValidacaoDaBiblioteca`) também é
    /// `arquivoInvalido`: a tela não distingue os motivos, e nada é gravado.
    func ler(_ dados: Data) throws -> ConteudoDaBiblioteca {
        let conteudo = try codificador.decodificar(dados)
        if ValidacaoDaBiblioteca.validar(conteudo) != nil {
            throw ErroDeImportacao.arquivoInvalido
        }
        return conteudo
    }

    /// Grava uma vez só, pela substituição atômica do repositório. Valida de novo (é barato): quem chama não
    /// precisa ter passado por `ler` (os dados de exemplo não passam), e conteúdo incoerente nunca chega ao banco.
    func importar(_ conteudo: ConteudoDaBiblioteca, modo: Modo) async throws {
        if ValidacaoDaBiblioteca.validar(conteudo) != nil {
            throw ErroDeImportacao.arquivoInvalido
        }
        let final: ConteudoDaBiblioteca
        switch modo {
        case .mesclar:
            final = Mesclagem.mesclar(aparelho: try await repositorio.conteudoInteiro(), arquivo: conteudo)
        case .substituir:
            final = conteudo
        }
        try await repositorio.substituirBiblioteca(por: final)
    }
}
