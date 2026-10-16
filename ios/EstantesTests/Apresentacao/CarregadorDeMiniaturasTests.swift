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

    func testFotoInteiraSaiComOLadoMaiorGuardado() async throws {
        let repositorio = BibliotecaRepositorioEmMemoria(livros: [livro])
        repositorio.fotos[livro.id] = Self.jpeg(largura: 1600, altura: 2400)
        let carregador = CarregadorDeMiniaturas(repositorio: repositorio)

        let inteira = await carregador.fotoInteira(doLivro: livro.id)

        // 1600 × 2400 com o lado maior em 1200 (o tamanho guardado): 800 × 1200.
        let imagem = try XCTUnwrap(inteira?.cgImage)
        XCTAssertEqual(imagem.width, 800)
        XCTAssertEqual(imagem.height, 1200)
    }

    func testMiniaturaContinuaPequenaDepoisDeAmpliar() async throws {
        let repositorio = BibliotecaRepositorioEmMemoria(livros: [livro])
        repositorio.fotos[livro.id] = Self.jpeg(largura: 800, altura: 1200)
        let carregador = CarregadorDeMiniaturas(repositorio: repositorio)
        _ = await carregador.miniatura(doLivro: livro.id, ladoMaior: 132)

        _ = await carregador.fotoInteira(doLivro: livro.id)
        let depois = await carregador.miniatura(doLivro: livro.id, ladoMaior: 132)

        // Se a inteira entrasse no cache, a lista desenharia a de 800 × 1200; a miniatura é 88 × 132.
        XCTAssertEqual(try XCTUnwrap(depois?.cgImage).width, 88)
    }

    func testFotoInteiraSemFotoDevolveNil() async {
        let repositorio = BibliotecaRepositorioEmMemoria(livros: [livro])
        let carregador = CarregadorDeMiniaturas(repositorio: repositorio)

        let inteira = await carregador.fotoInteira(doLivro: livro.id)

        XCTAssertNil(inteira)
    }

    func testTemFotoDepoisDaMiniaturaNaoLeAPorta() async {
        let repositorio = BibliotecaRepositorioEmMemoria(livros: [livro])
        repositorio.fotos[livro.id] = Self.jpeg(largura: 300, altura: 450)
        let carregador = CarregadorDeMiniaturas(repositorio: repositorio)
        _ = await carregador.miniatura(doLivro: livro.id, ladoMaior: 132)

        let tem = await carregador.temFoto(doLivro: livro.id)

        XCTAssertTrue(tem)
        XCTAssertEqual(repositorio.leiturasDeFoto, 1)
    }

    func testTemFotoSemCacheRespondePelaPortaSemGuardar() async {
        let semFoto = Livro(estanteId: livro.estanteId, titulo: "Teoria pura do direito")
        let repositorio = BibliotecaRepositorioEmMemoria(livros: [livro, semFoto])
        repositorio.fotos[livro.id] = Self.jpeg(largura: 300, altura: 450)
        let carregador = CarregadorDeMiniaturas(repositorio: repositorio)

        let primeira = await carregador.temFoto(doLivro: livro.id)
        let segunda = await carregador.temFoto(doLivro: livro.id)
        let doSemFoto = await carregador.temFoto(doLivro: semFoto.id)

        XCTAssertTrue(primeira)
        XCTAssertTrue(segunda)
        XCTAssertFalse(doSemFoto)
        // A primeira não deixou nada no cache (uma imagem de tamanho qualquer seria lixo): a segunda lê de novo.
        XCTAssertEqual(repositorio.leiturasDeFoto, 3)
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
