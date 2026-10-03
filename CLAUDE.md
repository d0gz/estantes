# Estantes — app iOS de estantes virtuais para livros jurídicos

## Leia antes de qualquer tarefa
- `docs/PLANO.md` — arquitetura, decisões já tomadas (com motivo) e checklist de cada fase.
  Não reabra uma decisão registrada ali sem avisar o Ricardo e explicar por quê.
- `docs/aprendizado/fase-N.md` da fase atual — o que já foi feito e aprendido.

## Objetivo do projeto
Este projeto existe para **aprender**, não só para entregar um app. O dono do repositório
(Ricardo) quer entender a fundo cada camada — do repositório ao deploy: algoritmos,
padrões, funcionamento interno e, principalmente, **o porquê de cada escolha**.

## Stack
- iOS: Swift 5, SwiftUI, **Core Data**, Vision (`VNDetectBarcodesRequest`, `VNRecognizeTextRequest`)
- Backend: Supabase (Postgres + `pg_trgm` + `unaccent`, RPC `buscar_livro`, Edge Functions em TypeScript/Deno)
- Dados: dataset LexML filtrado para registros do tipo "Livro"
- Fallbacks: Google Books API → Gemini (chaves só nas Edge Functions, nunca no app)
- CI: GitHub Actions, runner `macos-26` com Xcode 26 (testes a cada push; `.ipa` sem assinatura no "Run workflow")
- Instalação no iPhone: Sideloadly com Apple ID gratuito (o app vale 7 dias)

## Ambiente: dois Xcodes (regra crítica)
O Mac do Ricardo (MacBook Pro 15" 2015) roda macOS Monterey com **Xcode 14.2 / Swift 5.7**.
A CI roda **Xcode 26**. Todo código precisa compilar nos dois. Portanto:
- Versão mínima iOS 16; `SWIFT_VERSION = 5.0`.
- **Proibido**: SwiftData, `@Observable`, macro `#Preview`, Swift Testing (`import Testing`),
  qualquer API marcada `@available(iOS 17, *)` ou mais nova sem `if #available`, macros em geral.
- Use: Core Data, `ObservableObject` + `@Published`, `PreviewProvider`, XCTest, `NavigationStack`.
- O projeto é gerado pelo XcodeGen a partir de `ios/project.yml` (`projectFormat: xcode14_0`).
  Nunca edite nem commite `Estantes.xcodeproj`. Arquivos novos em `ios/Estantes/` entram sozinhos.
- O Claude Code não roda Xcode nesta máquina/sessão: depois de mudar Swift, avise o Ricardo para
  rodar `xcodegen generate` e testar no Xcode 14.2, e confira o resultado da CI.

## Estrutura
- `ios/project.yml` — definição do projeto (XcodeGen)
- `ios/Estantes/`, `ios/EstantesTests/` — código e testes
- `.github/workflows/` — `ios.yml` (testes e .ipa) e `supabase-keepalive.yml`
- `data/` — scripts de inspeção e limpeza do LexML
- `supabase/` — migrations e Edge Functions
- `docs/aprendizado/fase-N.md` — log de aprendizado de cada fase (mantido pelo teacher)
- `docs/guias/fase-N.pdf` — guia consolidado de cada fase

## Fase atual
Fase 0 — Ambiente. (Atualize esta linha ao abrir uma nova fase.)

## Regras de trabalho
1. **Explique antes de fazer.** Antes de cada mudança relevante, diga em poucas linhas o que
   vai fazer, por quê, e qual alternativa foi descartada.
2. **Ricardo escreve parte do código.** Quando uma tarefa estiver marcada com `[eu escrevo]`,
   não escreva a solução: dê o enunciado, as dicas necessárias e atue como revisor do código dele.
3. **Ao concluir cada tarefa**, chame o subagente `teacher` passando:
   - a fase atual (N);
   - um resumo do que foi feito e das decisões tomadas;
   - a saída de `git diff` (ou `git diff HEAD~1` se já houve commit).
   O teacher acrescenta uma entrada em `docs/aprendizado/fase-N.md`. Não pule este passo.
4. **Ao fim da fase**, Ricardo roda `/fechar-fase`, que gera o guia consolidado e o PDF.
5. Commits pequenos, com mensagens em português no imperativo ("Adiciona modelo Estante").
6. Segredos (chaves de API, service role do Supabase) nunca entram no repositório.

## Uso de modelos (para economizar)
| Uso | Modelo |
| --- | --- |
| Desenvolvimento do dia a dia (sessão principal) | Sonnet |
| Planejamento de fase e decisões de arquitetura | Opus |
| `teacher` — registro por tarefa | Sonnet |
| `teacher-consolidador` — guia de fim de fase | Opus |
| `revisor` — revisão de código | Sonnet |

Troque o modelo da sessão com `/model` conforme a tarefa.
