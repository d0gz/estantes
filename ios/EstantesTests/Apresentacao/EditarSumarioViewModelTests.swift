import XCTest
@testable import Estantes

/// A folha "Editar sumário", com o repositório falso.
@MainActor
final class EditarSumarioViewModelTests: XCTestCase {
    private let estante = Estante(nome: "Escritório", criadaEm: Date(timeIntervalSinceReferenceDate: 1))
    private let idTitulo = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let idParagrafo = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private func livro() -> Livro {
        Livro(
            estanteId: estante.id, titulo: "Tratado de direito privado", autores: ["Miranda, Pontes de"],
            editora: "Borsoi", ano: 1965, prateleira: "caixa azul",
            itensSumario: [
                ItemSumario(id: idTitulo, nivel: 1, titulo: "Contrato coletivo de trabalho"),
                ItemSumario(
                    id: idParagrafo, nivel: 2, numeracao: "§ 5.108", titulo: "Conceito e natureza", pagina: "3"
                ),
            ]
        )
    }

    private func montar(_ livro: Livro) async -> (EditarSumarioViewModel, BibliotecaRepositorioEmMemoria) {
        let repositorio = BibliotecaRepositorioEmMemoria(estantes: [estante], livros: [livro])
        let viewModel = EditarSumarioViewModel(livroId: livro.id, repositorio: repositorio)
        await viewModel.carregar()
        return (viewModel, repositorio)
    }

    private func editar(
        _ viewModel: EditarSumarioViewModel, _ id: UUID, _ mudar: (inout RascunhoSumario.Item) -> Void
    ) {
        guard var item = viewModel.item(id: id) else { return XCTFail("item \(id) não existe") }
        mudar(&item)
        viewModel.atualizar(item)
    }

    // MARK: T8 — salvar

    func testCarregarTrazOsItensDoLivroSemAlteracao() async {
        let (viewModel, _) = await montar(livro())

        XCTAssertEqual(viewModel.itens.map(\.titulo), ["Contrato coletivo de trabalho", "Conceito e natureza"])
        XCTAssertFalse(viewModel.alterado)
    }

    /// Só o sumário muda: título, autores e prateleira continuam os do livro.
    func testSalvarGravaOsItensEPreservaORestoDoLivro() async {
        let original = livro()
        let (viewModel, repositorio) = await montar(original)
        editar(viewModel, idParagrafo) { $0.pagina = " 5 " }

        let salvou = await viewModel.salvar()

        var esperado = original
        esperado.itensSumario[1].pagina = "5"
        XCTAssertTrue(salvou)
        XCTAssertEqual(repositorio.livrosGuardados[original.id], esperado)
    }

    func testSalvarComErroNaoGravaEMostraOErroNoItem() async {
        let original = livro()
        let (viewModel, repositorio) = await montar(original)
        editar(viewModel, idParagrafo) { $0.titulo = "  " }
        XCTAssertTrue(viewModel.alterado)
        XCTAssertNil(viewModel.erro(doItem: idParagrafo), "o erro só aparece depois de tentar salvar")

        let salvou = await viewModel.salvar()

        XCTAssertFalse(salvou)
        XCTAssertEqual(repositorio.livrosGuardados[original.id], original)
        XCTAssertEqual(viewModel.erro(doItem: idParagrafo), "Falta o título.")
        XCTAssertNil(viewModel.erro(doItem: idTitulo))
    }

    /// Apagar o título deixa o § (nível 2) em primeiro.
    func testSaltoNoPrimeiroItemTemMensagemPropria() async {
        let (viewModel, _) = await montar(livro())
        viewModel.apagar(id: idTitulo)

        _ = await viewModel.salvar()

        XCTAssertEqual(viewModel.erro(doItem: idParagrafo), "O primeiro item precisa ser de nível 1.")
    }

    /// O aviso não espera o "Salvar" e não impede de gravar.
    func testAvisoDePaginaApareceAntesDeSalvarENaoImpede() async {
        let (viewModel, _) = await montar(livro())
        editar(viewModel, idTitulo) { $0.pagina = "9" }

        XCTAssertEqual(viewModel.aviso(doItem: idParagrafo), "A página é menor que a do item anterior.")
        let salvou = await viewModel.salvar()
        XCTAssertTrue(salvou)
    }

    /// Depois do "Salvar" com erro, corrigir o item tira a marca dele (a validação acompanha a edição).
    func testErroSomeDepoisDeCorrigido() async {
        let (viewModel, _) = await montar(livro())
        editar(viewModel, idParagrafo) { $0.titulo = "" }
        _ = await viewModel.salvar()
        XCTAssertEqual(viewModel.quantidadeDeItensComErro, 1)

        editar(viewModel, idParagrafo) { $0.titulo = "Conceito" }

        XCTAssertNil(viewModel.erro(doItem: idParagrafo))
        XCTAssertEqual(viewModel.quantidadeDeItensComErro, 0)
    }

    func testFalhaAoGravarAvisaEMantemOsItens() async {
        let (viewModel, repositorio) = await montar(livro())
        editar(viewModel, idParagrafo) { $0.pagina = "5" }
        repositorio.falharAoGravar = true

        let salvou = await viewModel.salvar()

        XCTAssertFalse(salvou)
        XCTAssertEqual(viewModel.mensagemDeErro, "Não foi possível salvar o sumário.")
        XCTAssertEqual(viewModel.item(id: idParagrafo)?.pagina, "5")
    }

    // MARK: T9 — próximo item e item vazio

    /// O nível vem do item que acabou de ser digitado, mesmo depois de mudado no `Stepper`.
    func testProximoItemEntraLogoAbaixoComONivelDoItemDigitado() async {
        let (viewModel, _) = await montar(livro())
        let primeiro = viewModel.inserir(abaixoDe: idTitulo)!
        editar(viewModel, primeiro) { $0.nivel = 2; $0.titulo = "Capítulo I" }

        let segundo = viewModel.inserir(abaixoDe: primeiro)!

        XCTAssertEqual(viewModel.itens.map(\.id), [idTitulo, primeiro, segundo, idParagrafo])
        XCTAssertEqual(viewModel.item(id: segundo)?.nivel, 2)
    }

    func testItemSemNadaEscritoSaiAoVoltar() async {
        let (viewModel, _) = await montar(livro())
        let novo = viewModel.adicionarNoFim()

        viewModel.descartarSeVazio(id: novo)

        XCTAssertEqual(viewModel.itens.map(\.id), [idTitulo, idParagrafo])
    }

    /// Só a página já é algo escrito: o item fica (e a validação aponta o título que falta).
    func testItemSoComPaginaFicaAoVoltar() async {
        let (viewModel, _) = await montar(livro())
        let novo = viewModel.adicionarNoFim()
        editar(viewModel, novo) { $0.pagina = "12" }

        viewModel.descartarSeVazio(id: novo)

        XCTAssertEqual(viewModel.itens.map(\.id), [idTitulo, idParagrafo, novo])
    }
}
