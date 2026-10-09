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
- iOS: Swift 5, SwiftUI, **Core Data**, Vision (`VNDetectBarcodesRequest`, `VNRecognizeTextRequest`),
  VisionKit (`VNDocumentCameraViewController`, para o sumário)
- Backend: Supabase (Postgres + `pg_trgm` + `unaccent`, RPC `buscar_livro`, Edge Functions em TypeScript/Deno)
- Dados: dataset LexML filtrado para registros do tipo "Livro"
- Fallbacks: Google Books API → Gemini (chaves só nas Edge Functions, nunca no app)
- CI: GitHub Actions, runner `macos-26` com Xcode 26 (testes em push no main e em PRs que mexem em `ios/`; `.ipa` sem assinatura no "Run workflow")
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
- O Claude Code roda no próprio Mac (Monterey, apesar de não ser suportado oficialmente). Depois de
  mudar código Swift, rode `./scripts/testar.sh` antes de commitar: ele faz `cd ios && xcodegen generate`
  e `xcodebuild test -project Estantes.xcodeproj -scheme Estantes -destination 'platform=iOS Simulator,name=iPhone 14'`.
  Depois do push, acompanhe a CI (Xcode 26) com o `gh`.
- Ferramentas na máquina: Xcode 14.2 (`/Applications/Xcode.app`, via `xcode-select`), XcodeGen 2.46.0
  (binário em `/usr/local/bin`; não reinstale nem atualize), `gh` autenticado (abrir PRs com
  `gh pr create`, acompanhar a CI com `gh run list`/`gh run view`).

## Arquitetura (regra crítica — detalhes em docs/PLANO.md)
- MVVM em camadas: `Dominio/` (structs, regras puras, casos de uso, protocolos) ← `Dados/` e `Apresentacao/`.
- `Dominio/` importa só Foundation: nada de SwiftUI, CoreData, Vision ou rede.
- `NSManagedObject` só existe dentro de `Dados/Persistencia/`; telas e ViewModels usam structs.
- Dependências entram pelo `init`; a montagem fica em `App/Dependencias`. Sem singletons.
- Toda regra nova do Domínio nasce com teste XCTest em `EstantesTests/Dominio/`.
- A busca é **só local** (biblioteca do usuário, offline): índice invertido + BM25F em `Dominio/Busca/`.

## Estrutura
- `ios/project.yml` — definição do projeto (XcodeGen)
- `ios/Estantes/`, `ios/EstantesTests/` — código e testes
- `.github/workflows/` — `ios.yml` (testes e .ipa) e `supabase-keepalive.yml`
- `data/` — scripts de inspeção e limpeza do LexML
- `supabase/` — migrations e Edge Functions
- `docs/aprendizado/fase-N.md` — log de aprendizado de cada fase (mantido pelo teacher)
- `docs/guias/fase-N.md` — guia consolidado de cada fase (só Markdown, sem PDF)

## Fase atual
Fase 2 — App. (Atualize esta linha ao abrir uma nova fase.)
Concluídas: 2.1 (entidades, porta e `ValidacaoSumario`) e 2.2 (Core Data e repositório).
**Em andamento: 2.3 — motor de busca**, branch `fase2/busca` (PR em rascunho). Passos 1–6 prontos
(tokenizador, índice invertido, BM25F, filtros, motor + resultado, consultas de referência com o peso do sumário
ajustado para 0,5) e a tarefa 2.3b (obras em vários volumes); 185 testes.
**Próximo: decidir as sondas em aberto** (E estrito → "E, e se vazio, OU"? indexar volume/artigos? plural?),
listadas em `docs/PLANO.md` (Busca na biblioteca), e depois fechar a 2.3 (PR) e seguir para a 2.4. Ordem das tarefas em `docs/PLANO.md` (Checklist da Fase 2).

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
4. **Ao fim da fase**, Ricardo roda `/fechar-fase`, que gera o guia consolidado em Markdown.
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

## Economia de contexto
- Para testar o app, rode `./scripts/testar.sh` (gera o projeto e mostra só erros e o resumo).
  Não rode `xcodebuild` direto: a saída tem milhares de linhas. Se precisar do detalhe de um erro,
  leia trechos do log indicado pelo script com `grep`/`tail`, nunca o arquivo inteiro.
- Não leia os arquivos grandes de `data/` (CSV, JSONL, cache_urn): consulte com `head`, `wc -l`
  ou scripts. O `.claude/settings.json` bloqueia a leitura direta deles.
- Para GitHub (PRs, CI, artefatos), use o `gh` em vez de abrir páginas.
- Uma tarefa por sessão; ao trocar de assunto, sugira ao Ricardo usar `/clear`.

# Compact instructions
Ao compactar, preserve: a fase e a tarefa atuais, decisões tomadas na sessão, arquivos alterados,
comandos de teste e o resultado do último teste. Descarte saídas longas de comandos e conteúdo de
arquivos já lidos.
