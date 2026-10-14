import UIKit
import XCTest
@testable import Estantes

final class RedutorDeFotoTests: XCTestCase {
    /// Uma foto JPEG de `largura` × `altura` pixels (escala 1: ponto = pixel).
    private func foto(largura: Int, altura: Int) -> Data {
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        let tamanho = CGSize(width: largura, height: altura)
        return UIGraphicsImageRenderer(size: tamanho, format: formato).jpegData(withCompressionQuality: 0.9) { contexto in
            UIColor.systemTeal.setFill()
            contexto.fill(CGRect(origin: .zero, size: tamanho))
        }
    }

    private func pixels(_ dados: Data) throws -> CGSize {
        let imagem = try XCTUnwrap(UIImage(data: dados)?.cgImage)
        return CGSize(width: imagem.width, height: imagem.height)
    }

    func testFotoGrandeSaiComLadoMaiorDe1200NaMesmaProporcao() throws {
        let guardada = try XCTUnwrap(RedutorDeFoto.paraGuardar(foto(largura: 4000, altura: 3000)))

        XCTAssertEqual(try pixels(guardada), CGSize(width: 1200, height: 900))
    }

    func testFotoMenorQue1200NaoEhAmpliada() throws {
        let guardada = try XCTUnwrap(RedutorDeFoto.paraGuardar(foto(largura: 600, altura: 400)))

        XCTAssertEqual(try pixels(guardada), CGSize(width: 600, height: 400))
    }

    func testDadosQueNaoSaoImagemDevolvemNil() {
        // A tela usa o `nil` para dizer "Não foi possível abrir a foto." (ex.: um PDF escolhido por engano).
        let texto = Data("não é uma foto".utf8)

        XCTAssertNil(RedutorDeFoto.paraGuardar(texto))
    }
}
