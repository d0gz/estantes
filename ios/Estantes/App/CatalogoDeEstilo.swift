#if DEBUG
import SwiftUI

/// Catálogo dos tokens de estilo (Estilo 0c), só em DEBUG: `-captura Estilo` e `-captura EstiloTelas`.
/// Mostra cada token aplicado num pedaço de tela típico, para decidir olhando, e não por tabela.
/// Duas páginas porque o `simctl` não rola a tela: cada uma cabe numa captura do iPhone 14.
struct CatalogoDeEstiloView: View {
    enum Pagina { case fundamentos, telas, categorias }
    let pagina: Pagina

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espaco.grande) {
                switch pagina {
                case .fundamentos: fundamentos
                case .telas: telas
                case .categorias: categorias
                }
            }
            .padding(Espaco.padrao)
        }
        .background(Cor.fundo.ignoresSafeArea())
    }

    // MARK: Página 1 — cores, tipografia, botões, vidro, raios

    @ViewBuilder
    private var fundamentos: some View {
        secao("Cores") {
            HStack(spacing: Espaco.pequeno) {
                amostra("fundo", Cor.fundo)
                amostra("cartão", Cor.cartao)
                amostra("superfície", Cor.superficie)
                amostra("destaque", Cor.destaque)
                amostra("sobre", Cor.sobreDestaque)
                amostra("secund.", Cor.textoSecundario)
            }
        }
        secao("Tipografia") {
            VStack(alignment: .leading, spacing: Espaco.minimo) {
                Text("Tratado de direito privado").font(Fonte.tituloLivro)
                Text("Escritório").font(Fonte.tituloEstante)
                Text("Miranda, Pontes de · Borsoi, 1965").font(.body)
                Text("Tomo XLVIII · caixa azul").font(.subheadline).foregroundColor(Cor.textoSecundario)
            }
        }
        secao("Botões") {
            HStack(spacing: Espaco.medio) {
                Button("Salvar") {}.buttonStyle(EstiloPrincipal())
                Button("Editar") {}.buttonStyle(.bordered)
                Button("Ver todos") {}
            }
        }
        secao("Vidro sobre capa clara e escura") {
            HStack(spacing: Espaco.medio) {
                capaComVidro(Color(red: 0.95, green: 0.91, blue: 0.82))
                capaComVidro(Color(red: 0.17, green: 0.17, blue: 0.19))
            }
        }
        secao("Raios 8 · 12 · 20") {
            HStack(spacing: Espaco.padrao) {
                ForEach([Raio.pequeno, Raio.medio, Raio.grande], id: \.self) { raio in
                    Cor.superficie.frame(width: 56, height: 56).cantos(raio)
                }
            }
        }
    }

    // MARK: Página 2 — cartões, chips, estado vazio, formulário

    @ViewBuilder
    private var telas: some View {
        secao("Cartão de estante") {
            HStack(spacing: Espaco.medio) {
                CartaoDeEstante(nome: "Escritório", detalhe: "6 livros")
                CartaoDeEstante(nome: "Sala", detalhe: "1 livro")
            }
        }
        secao("Chips") {
            HStack(spacing: Espaco.pequeno) {
                chip("Escritório", icone: "books.vertical")
                chip("1965–1970", icone: "calendar")
                chip("Borsoi", icone: "building.columns")
            }
        }
        secao("Estado vazio") {
            IlustracaoEstanteVazia()
        }
        secao("Formulário em fundo branco") {
            VStack(alignment: .leading, spacing: 0) {
                linhaDeCampo("Título *")
                Divider().padding(.leading, Espaco.padrao)
                linhaDeCampo("Subtítulo")
                Divider().padding(.leading, Espaco.padrao)
                Label("Adicionar autor", systemImage: "plus.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(Cor.destaque)
                    .padding(Espaco.padrao)
            }
            .cartao()
        }
    }

    // MARK: Página 3 — chips de categoria (2.5: componente e tons em hex)

    private static let exemplos: [Categoria] = [
        Categoria(nome: "Constitucional", cor: .vermelho), Categoria(nome: "Civil", cor: .laranja),
        Categoria(nome: "Penal", cor: .amarelo), Categoria(nome: "Processo", cor: .verde),
        Categoria(nome: "Tributário", cor: .menta), Categoria(nome: "Trabalho", cor: .indigo),
        Categoria(nome: "Administrativo", cor: .roxo), Categoria(nome: "Empresarial", cor: .rosa),
        Categoria(nome: "Filosofia", cor: .marrom), Categoria(nome: "Ler depois", cor: .cinza),
    ]

    @ViewBuilder
    private var categorias: some View {
        secao("Categorias — as 10 cores e o fantasma") {
            FluxoDeChips {
                ForEach(Self.exemplos) { ChipDeCategoria($0) }
                ChipDeCategoria.fantasma
            }
        }
    }

    // MARK: Peças

    private func secao<Conteudo: View>(_ titulo: String, @ViewBuilder conteudo: () -> Conteudo) -> some View {
        VStack(alignment: .leading, spacing: Espaco.pequeno) {
            Text(titulo.uppercased()).font(.caption.weight(.semibold)).foregroundColor(Cor.textoSecundario)
            conteudo()
        }
    }

    private func amostra(_ nome: String, _ cor: Color) -> some View {
        VStack(spacing: Espaco.minimo) {
            cor.frame(width: 48, height: 48).cantos(Raio.medio)
                .overlay(RoundedRectangle(cornerRadius: Raio.medio, style: .continuous).stroke(.gray.opacity(0.3)))
            Text(nome).font(.caption2).foregroundColor(Cor.textoSecundario)
        }
    }

    private func capaComVidro(_ capa: Color) -> some View {
        capa.frame(height: 110).cantos(Raio.pequeno)
            .overlay {
                Button {} label: {
                    Image(systemName: "camera.fill").font(.title2).frame(width: 60, height: 60)
                }
                .buttonStyle(EstiloVidro())
            }
    }

    private func chip(_ texto: String, icone: String) -> some View {
        // Sobre a superfície clara: texto no `.primary`, destaque só no ícone (regra da paleta).
        HStack(spacing: Espaco.minimo) {
            Image(systemName: icone).foregroundColor(Cor.destaque)
            Text(texto)
        }
            .font(.subheadline)
            .padding(.horizontal, Espaco.medio)
            .padding(.vertical, Espaco.pequeno)
            .background(Cor.superficie, in: Capsule())
    }

    private func linhaDeCampo(_ placeholder: String) -> some View {
        Text(placeholder)
            .foregroundColor(Color(.placeholderText))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Espaco.padrao)
    }
}
#endif
