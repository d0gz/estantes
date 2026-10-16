import SwiftUI
import UIKit

extension View {
    /// Mostra `imagem` ampliada, por cima de tudo, enquanto ela não for `nil`; ao fechar, volta a `nil`.
    ///
    /// Apresentada pelo UIKit (`.overFullScreen`), e não com o `fullScreenCover`: no iOS 16 o `fullScreenCover` é
    /// opaco (tira a tela de baixo), e o fundo esmaecido precisa do Detalhe aparecendo atrás. O modificador que deixa
    /// o `fullScreenCover` transparente (`presentationBackground`) é do iOS 16.4.
    func fotoAmpliada(_ imagem: Binding<UIImage?>) -> some View {
        background(ApresentadorDaFotoAmpliada(imagem: imagem))
    }
}

/// Uma `UIView` invisível, só para chegar à janela e apresentar a partir do controlador que estiver no topo (sem
/// embutir um `UIViewController` filho na tela). Use dentro do conteúdo rolável, nunca em volta da `ScrollView`: uma
/// vista do UIKit envolvendo a tela inteira impede a barra de navegação de reconhecer a rolagem (ver `LivroDetalheView`).
private struct ApresentadorDaFotoAmpliada: UIViewRepresentable {
    @Binding var imagem: UIImage?

    func makeUIView(context: Context) -> UIView {
        let vista = UIView()
        vista.isUserInteractionEnabled = false
        return vista
    }

    func updateUIView(_ vista: UIView, context: Context) {
        guard let imagem = imagem, var topo = vista.window?.rootViewController else { return }
        while let apresentado = topo.presentedViewController {
            topo = apresentado
        }
        // Já aberta (o SwiftUI pode chamar o update de novo enquanto ela está na tela).
        guard !(topo is FotoAmpliadaController) else { return }
        let fechar = { [binding = $imagem] in binding.wrappedValue = nil }
        topo.present(FotoAmpliadaController(imagem: imagem, aoFechar: fechar), animated: true)
    }
}

/// A foto sobre um fundo escuro esmaecido, com zoom (pinça, arrastar e duplo toque) pela `UIScrollView`, que dá os
/// limites e a mola nativos; o `ScrollView` do SwiftUI no iOS 16 não tem zoom. Fecha com "Fechar" ou puxando a foto
/// (sem zoom): o escuro some conforme ela se afasta.
final class FotoAmpliadaController: UIViewController {
    /// Escuro, mas não opaco: o Detalhe aparece de leve atrás.
    private static let opacidadeDoFundo: CGFloat = 0.88
    private static let zoomDoDuploToque: CGFloat = 2.5
    /// Quanto arrastar (em pontos) para fechar ao soltar; ou um puxão rápido.
    private static let distanciaParaFechar: CGFloat = 120
    private static let velocidadeParaFechar: CGFloat = 800
    /// A foto sai da tela depressa ao fechar; ao voltar, com mola amortecida (sem quicar demais).
    private static let duracaoDaSaida: TimeInterval = 0.25
    private static let duracaoDaVolta: TimeInterval = 0.4
    private static let amortecimentoDaVolta: CGFloat = 0.8

    private let imagem: UIImage
    private let aoFechar: () -> Void
    private let fundo = UIView()
    private let rolagem = UIScrollView()
    private let vistaDaImagem = UIImageView()
    private let botaoFechar = UIButton(type: .close)

    init(imagem: UIImage, aoFechar: @escaping () -> Void) {
        self.imagem = imagem
        self.aoFechar = aoFechar
        super.init(nibName: nil, bundle: nil)
        // Por cima da tela atual, sem tirá-la; entra e sai esmaecendo.
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        modalPresentationCapturesStatusBarAppearance = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        // O VoiceOver fica preso aqui enquanto a foto está aberta.
        view.accessibilityViewIsModal = true

        fundo.backgroundColor = UIColor.black.withAlphaComponent(Self.opacidadeDoFundo)
        fundo.frame = view.bounds
        fundo.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(fundo)

        rolagem.frame = view.bounds
        rolagem.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        rolagem.delegate = self
        rolagem.maximumZoomScale = 4
        rolagem.showsVerticalScrollIndicator = false
        rolagem.showsHorizontalScrollIndicator = false
        rolagem.contentInsetAdjustmentBehavior = .never
        view.addSubview(rolagem)

        vistaDaImagem.image = imagem
        vistaDaImagem.isAccessibilityElement = true
        vistaDaImagem.accessibilityLabel = "Foto do livro"
        vistaDaImagem.accessibilityTraits = .image
        rolagem.addSubview(vistaDaImagem)

        botaoFechar.overrideUserInterfaceStyle = .dark
        botaoFechar.accessibilityLabel = "Fechar"
        botaoFechar.addTarget(self, action: #selector(fechar), for: .touchUpInside)
        botaoFechar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(botaoFechar)
        NSLayoutConstraint.activate([
            botaoFechar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            botaoFechar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])

        let duploToque = UITapGestureRecognizer(target: self, action: #selector(alternarZoom(_:)))
        duploToque.numberOfTapsRequired = 2
        rolagem.addGestureRecognizer(duploToque)

        let puxar = UIPanGestureRecognizer(target: self, action: #selector(puxar(_:)))
        puxar.delegate = self
        view.addGestureRecognizer(puxar)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Só no tamanho inicial: com zoom, o tamanho da imagem é da `UIScrollView`.
        guard rolagem.zoomScale == rolagem.minimumZoomScale else { return }
        vistaDaImagem.frame = CGRect(origin: .zero, size: tamanhoAjustado)
        rolagem.contentSize = vistaDaImagem.frame.size
        centralizar()
    }

    /// A imagem inteira na tela, na proporção dela.
    private var tamanhoAjustado: CGSize {
        let limite = view.bounds.size
        guard imagem.size.width > 0, imagem.size.height > 0 else { return limite }
        let escala = min(limite.width / imagem.size.width, limite.height / imagem.size.height)
        return CGSize(width: imagem.size.width * escala, height: imagem.size.height * escala)
    }

    /// Menor que a tela (sem zoom, ou numa direção só), a imagem fica no meio em vez de grudar no canto.
    private func centralizar() {
        let sobraX = max(0, (rolagem.bounds.width - rolagem.contentSize.width) / 2)
        let sobraY = max(0, (rolagem.bounds.height - rolagem.contentSize.height) / 2)
        rolagem.contentInset = UIEdgeInsets(top: sobraY, left: sobraX, bottom: sobraY, right: sobraX)
    }

    @objc private func fechar() {
        dismiss(animated: true, completion: aoFechar)
    }

    override func accessibilityPerformEscape() -> Bool {
        fechar()
        return true
    }

    /// Sem zoom, aproxima no ponto tocado; com zoom, volta ao tamanho inteiro.
    @objc private func alternarZoom(_ toque: UITapGestureRecognizer) {
        guard rolagem.zoomScale == rolagem.minimumZoomScale else {
            rolagem.setZoomScale(rolagem.minimumZoomScale, animated: true)
            return
        }
        let ponto = toque.location(in: vistaDaImagem)
        let tamanho = CGSize(
            width: rolagem.bounds.width / Self.zoomDoDuploToque,
            height: rolagem.bounds.height / Self.zoomDoDuploToque
        )
        let area = CGRect(origin: CGPoint(x: ponto.x - tamanho.width / 2, y: ponto.y - tamanho.height / 2), size: tamanho)
        rolagem.zoom(to: area, animated: true)
    }

    /// Puxar a foto: ela acompanha o dedo e o escuro some na proporção; ao soltar, fecha ou volta com mola.
    @objc private func puxar(_ gesto: UIPanGestureRecognizer) {
        let deslocamento = gesto.translation(in: view)
        let progresso = min(1, abs(deslocamento.y) / (view.bounds.height / 2))
        switch gesto.state {
        case .changed:
            rolagem.transform = CGAffineTransform(translationX: deslocamento.x, y: deslocamento.y)
            fundo.alpha = 1 - progresso
            botaoFechar.alpha = 1 - progresso
        case .ended, .cancelled:
            let velocidade = gesto.velocity(in: view).y
            if gesto.state == .ended,
               abs(deslocamento.y) > Self.distanciaParaFechar || abs(velocidade) > Self.velocidadeParaFechar {
                // Continua o movimento para fora da tela e só então fecha, sem o esmaecer do `dismiss`.
                let destino = (deslocamento.y >= 0 ? 1 : -1) * view.bounds.height
                UIView.animate(withDuration: Self.duracaoDaSaida, delay: 0, options: .curveEaseOut) {
                    self.rolagem.transform = CGAffineTransform(translationX: deslocamento.x, y: destino)
                    self.fundo.alpha = 0
                    self.botaoFechar.alpha = 0
                } completion: { _ in
                    self.dismiss(animated: false, completion: self.aoFechar)
                }
            } else {
                UIView.animate(
                    withDuration: Self.duracaoDaVolta, delay: 0,
                    usingSpringWithDamping: Self.amortecimentoDaVolta, initialSpringVelocity: 0
                ) {
                    self.rolagem.transform = .identity
                    self.fundo.alpha = 1
                    self.botaoFechar.alpha = 1
                }
            }
        default:
            break
        }
    }
}

extension FotoAmpliadaController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        vistaDaImagem
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centralizar()
    }
}

extension FotoAmpliadaController: UIGestureRecognizerDelegate {
    /// Puxar para fechar só sem zoom (com zoom, arrastar é andar pela foto) e só num gesto mais vertical que horizontal.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let puxar = gestureRecognizer as? UIPanGestureRecognizer,
              rolagem.zoomScale == rolagem.minimumZoomScale
        else { return false }
        let velocidade = puxar.velocity(in: view)
        return abs(velocidade.y) > abs(velocidade.x)
    }
}
