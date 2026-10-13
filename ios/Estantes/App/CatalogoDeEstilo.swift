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
        secao("Cartão branco com sombra · cartão na superfície") {
            HStack(spacing: Espaco.medio) {
                cartaoDeEstante(fundo: Cor.cartao, sombra: true)
                cartaoDeEstante(fundo: Cor.superficie, sombra: false)
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
            HStack(alignment: .bottom, spacing: Espaco.pequeno) {
                ForEach([70, 90, 60, 80], id: \.self) { altura in
                    Cor.superficie.frame(width: 22, height: CGFloat(altura)).cantos(4)
                }
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(Cor.sobreDestaque)
                    .frame(width: 52, height: 52)
                    .background(Cor.destaque, in: Circle())
                    .padding(.leading, Espaco.padrao)
            }
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
            .background(Cor.cartao)
            .cantos(Raio.grande)
            .sombraSuave()
        }
    }

    // MARK: Página 3 — chips de categoria (protótipo para a 2.5)

    /// Categorias de exemplo, cada uma com uma cor do sistema (sem azul, ciano e teal: são do destaque) e o tom
    /// escuro do mesmo matiz para o texto no claro (escurecido só até 4,6:1 sobre o fundo pastel).
    private static let exemplos: [(nome: String, cor: UIColor, textoClaro: UInt32)] = [
        ("Constitucional", .systemRed, 0xCE0B00), ("Civil", .systemOrange, 0x9E5C00),
        ("Penal", .systemYellow, 0x876C00), ("Processo", .systemGreen, 0x207C38),
        ("Tributário", .systemMint, 0x007873), ("Trabalho", .systemIndigo, 0x5654D6),
        ("Administrativo", .systemPurple, 0x9D2BD7), ("Empresarial", rosa, 0xCB0062),
        ("Filosofia", .systemBrown, 0x7D6648),
    ]

    /// Rosa próprio (matiz 331°): o `systemPink` (349°) ficava a 14° do vermelho e se confundia com ele.
    private static let rosa = UIColor(claro: 0xFF2D92, escuro: 0xFF7AC0)

    @ViewBuilder
    private var categorias: some View {
        secao("Categorias — pastel, contorno vivo, texto escuro do matiz") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Espaco.pequeno, alignment: .leading)],
                      alignment: .leading, spacing: Espaco.pequeno) {
                ForEach(Self.exemplos, id: \.nome) { exemplo in
                    chipDeCategoria(exemplo.nome, cor: exemplo.cor, textoClaro: exemplo.textoClaro)
                }
            }
        }
    }

    /// Claro: a identidade vem do fundo pastel e do contorno vivo; o texto é o mesmo matiz, mais escuro.
    /// Escuro: texto e contorno na variante de alto contraste, sobre um véu da cor.
    private func chipDeCategoria(_ nome: String, cor: UIColor, textoClaro: UInt32) -> some View {
        let forte = Self.comAltoContraste(cor)
        let viva = Color(uiColor: UIColor { tracos in
            (tracos.userInterfaceStyle == .dark ? forte : cor).resolvedColor(with: tracos)
        })
        let texto = Color(uiColor: UIColor { tracos in
            tracos.userInterfaceStyle == .dark ? forte.resolvedColor(with: tracos) : UIColor(claro: textoClaro, escuro: textoClaro)
        })
        return HStack(spacing: Espaco.minimo) {
            Image(systemName: "tag").foregroundColor(viva)
            Text(nome).foregroundColor(texto)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, Espaco.medio)
        .padding(.vertical, Espaco.pequeno)
        // O primeiro `background` fica por cima: véu da cor sobre o fundo do cartão.
        .background(Color(uiColor: cor).opacity(0.15), in: Capsule())
        .background(Cor.cartao, in: Capsule())
        .overlay(Capsule().strokeBorder(viva, lineWidth: 1))
    }

    /// A mesma cor do sistema na variante que o iOS usa com "Aumentar contraste" (mais escura no claro,
    /// mais clara no escuro), mantendo o modo claro/escuro de quem pede.
    private static func comAltoContraste(_ cor: UIColor) -> UIColor {
        UIColor { tracos in
            cor.resolvedColor(with: UITraitCollection(traitsFrom: [tracos, UITraitCollection(accessibilityContrast: .high)]))
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

    private func cartaoDeEstante(fundo: Color, sombra: Bool) -> some View {
        VStack(alignment: .leading, spacing: Espaco.minimo) {
            Image(systemName: "books.vertical.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(Cor.destaque)
                .font(.title3)
            Text("Escritório").font(Fonte.tituloEstante)
            Text("6 livros").font(.subheadline).foregroundColor(Cor.textoSecundario)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .padding(Espaco.medio)
        .background(fundo)
        .cantos(Raio.grande)
        .modifier(SombraOpcional(ligada: sombra))
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

private struct SombraOpcional: ViewModifier {
    let ligada: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if ligada { content.sombraSuave() } else { content }
    }
}
#endif
