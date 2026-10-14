import UIKit
import XCTest
@testable import Estantes

final class CarregadorDeMiniaturasTests: XCTestCase {
    private let livro = Livro(estanteId: UUID(), titulo: "Tratado de direito privado")

    func testSemFotoDevolveNil() async {
        let repositorio = BibliotecaRepositorioEmMemoria(livros: [livro])
        let carregador = CarregadorDeMiniaturas(repositorio: repositorio)

        let miniatura = await carregador.miniatura(doLivro: livro.id, ladoMaior: 132)

        XCTAssertNil(miniatura)
    }

    func testReduzAFotoAoLadoMaiorPedido() async throws {
        let repositorio = BibliotecaRepositorioEmMemoria(livros: [livro])
        repositorio.fotos[livro.id] = Self.jpeg(largura: 300, altura: 450)
        let carregador = CarregadorDeMiniaturas(repositorio: repositorio)

        let miniatura = await carregador.miniatura(doLivro: livro.id, ladoMaior: 132)

        // 300 × 450 com o lado maior em 132: 88 × 132 (mesma proporção 2:3), em pixels.
        let imagem = try XCTUnwrap(miniatura?.cgImage)
        XCTAssertEqual(imagem.width, 88)
        XCTAssertEqual(imagem.height, 132)
    }

    func testSegundaLeituraVemDoCache() async {
        let repositorio = BibliotecaRepositorioEmMemoria(livros: [livro])
        repositorio.fotos[livro.id] = Self.jpeg(largura: 300, altura: 450)
        let carregador = CarregadorDeMiniaturas(repositorio: repositorio)

        _ = await carregador.miniatura(doLivro: livro.id, ladoMaior: 132)
        let segunda = await carregador.miniatura(doLivro: livro.id, ladoMaior: 132)

        XCTAssertNotNil(segunda)
        XCTAssertEqual(repositorio.leiturasDeFoto, 1)
    }

    func testPedidoMaiorQueOGuardadoReduzDeNovo() async throws {
        let repositorio = BibliotecaRepositorioEmMemoria(livros: [livro])
        repositorio.fotos[livro.id] = Self.jpeg(largura: 300, altura: 450)
        let carregador = CarregadorDeMiniaturas(repositorio: repositorio)

        _ = await carregador.miniatura(doLivro: livro.id, ladoMaior: 132)
        let maior = await carregador.miniatura(doLivro: livro.id, ladoMaior: 264)

        // Texto aumentado com o app aberto: a de 132 ficaria borrada. 300 × 450 com o lado maior em 264: 176 × 264.
        let imagem = try XCTUnwrap(maior?.cgImage)
        XCTAssertEqual(imagem.width, 176)
        XCTAssertEqual(imagem.height, 264)
        XCTAssertEqual(repositorio.leiturasDeFoto, 2)
    }

    func testDepoisDeEsquecerLeDaPortaDeNovo() async {
        let repositorio = BibliotecaRepositorioEmMemoria(livros: [livro])
        repositorio.fotos[livro.id] = Self.jpeg(largura: 300, altura: 450)
        let carregador = CarregadorDeMiniaturas(repositorio: repositorio)

        _ = await carregador.miniatura(doLivro: livro.id, ladoMaior: 132)
        // Foto trocada no formulário: a guardada no cache ficou velha.
        await carregador.esquecer(livro.id)
        _ = await carregador.miniatura(doLivro: livro.id, ladoMaior: 132)

        XCTAssertEqual(repositorio.leiturasDeFoto, 2)
    }

    /// JPEG de uma cor só, com o tamanho exato em pixels (escala 1).
    private static func jpeg(largura: Int, altura: Int) -> Data {
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        let tamanho = CGSize(width: largura, height: altura)
        let imagem = UIGraphicsImageRenderer(size: tamanho, format: formato).image { contexto in
            UIColor.brown.setFill()
            contexto.fill(CGRect(origin: .zero, size: tamanho))
        }
        return imagem.jpegData(compressionQuality: 0.8)!
    }
}
