# Fase 3 — Identificação de livros e sumário

Objetivo da fase: identificar livros (jurídicos ou não) por OCR da Apple + Gemini, com revisão do usuário, e capturar o sumário; o LexML fica como parte opcional.

## Ajuste — "Cancelar" da tela Busca à esquerda (2026-11-08)

Ajuste pedido pelo Ricardo, fora do checklist.

### O que foi feito
Em `ios/Estantes/Apresentacao/Busca/BuscaView.swift` (linha 56), o `ToolbarItem(placement: .confirmationAction)` virou `.cancellationAction`. O botão "Cancelar" saiu do canto direito e foi para o esquerdo, como em `LivroFormularioView`, `EditarSumarioView`, `EscolhaDeCategoriasView` e `CategoriaFormularioView`.

### Conceitos envolvidos
- **Placement semântico da toolbar.** Em SwiftUI você declara o *papel* do botão (`.confirmationAction`, `.cancellationAction`, `.primaryAction`...) e o sistema decide posição e peso visual conforme a plataforma. No iOS, `.confirmationAction` vai à direita e em negrito (convenção de "Salvar/OK"); `.cancellationAction` vai à esquerda, peso normal. O botão estava à direita porque declarava o papel errado, não por uma escolha de posição.
- **Conflito de posição.** O lado esquerdo só está livre porque a tela usa `.navigationBarBackButtonHidden(true)`. Com o botão de voltar visível, os dois disputariam o espaço.

### Por que assim
Usar o papel certo mantém a consistência com as outras telas "Cancelar" sem repetir decisão de layout, e se adapta a outras plataformas ou a mudanças do sistema (por exemplo, o visual do iOS 26).

### Alternativas descartadas
`.navigationBarLeading` fixa só a posição, sem dizer o que o botão faz. Funcionaria hoje, mas destoaria das demais telas e perderia a adaptação automática. Note também que `.navigationBarLeading` é posicional e não afeta o peso da fonte.

### Padrões e boas práticas
Prefira descrever intenção (papel) a descrever coordenadas. Evite isso só quando precisar de uma posição específica que nenhum papel expresse.

### Armadilhas
- O `docs/PLANO.md` (linhas 543 e 735) ainda diz "Cancelar à direita", herdado do desenho do `.searchable`, que põe o Cancelar à direita do campo. Esta mudança reverte esse detalhe; o PLANO precisa ser atualizado para não contradizer o código.
- Nenhum teste cobre a posição do botão (é só apresentação); a conferência foi visual, em `docs/capturas/Busca/Busca_3.1-escuro.png`.

### Para ir além
- Documentação Apple: `ToolbarItemPlacement` (`cancellationAction`, `confirmationAction`).
- Human Interface Guidelines, seção "Toolbars" e "Navigation bars".

### Perguntas
1. Com suas palavras: qual a diferença entre `.cancellationAction` e `.navigationBarLeading`, e por que a primeira é preferível aqui?
2. O que aconteceria se a tela removesse `.navigationBarBackButtonHidden(true)`?
3. Por que nenhum dos 548 testes pegaria este bug, e que tipo de verificação pegaria?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->
