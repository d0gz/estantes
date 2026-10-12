---
name: fechar-fase
description: Fecha uma fase do projeto — confere pendências, chama o teacher-consolidador para gerar o guia da fase em Markdown, e prepara a próxima. Use quando o Ricardo digitar /fechar-fase ou pedir para encerrar uma fase.
---

# Fechar uma fase

Argumento opcional: número da fase. Se não vier, use a "Fase atual" do `CLAUDE.md`.

## Passos

1. **Conferir pendências**
   - `git status`: se houver mudanças não commitadas, pergunte ao Ricardo se deve commitar antes.
   - Leia `docs/aprendizado/fase-N.md`. Liste as entradas cuja seção "Minhas respostas" está vazia
     e pergunte se ele quer respondê-las antes de consolidar (o guia fica melhor com elas).
   - Se a última entrada tiver respostas ainda não corrigidas, chame o subagente `teacher`
     pedindo apenas a correção dessa entrada.

2. **Auditar os testes da fase**
   - Liste os testes alterados na fase:
     `git diff --name-only fase-<N-1>..HEAD -- ios/EstantesTests` (para a fase 0, todos).
   - Chame o subagente `auditor-testes` só com esses arquivos (em lotes paralelos, se forem muitos).
   - Mostre o relatório ao Ricardo e pergunte o que corrigir antes de consolidar. Não corrija nada
     sem ele: alguns testes ele mesmo escreve.

3. **Consolidar**
   - Chame o subagente `teacher-consolidador` com o número da fase.
   - Ao terminar, confirme que existe `docs/guias/fase-N.md` (só Markdown; não há PDF).

4. **Registrar e preparar a próxima fase**
   - Commit: `Fecha fase N: guia de aprendizado`.
   - Crie uma tag git `fase-N`.
   - Atualize a linha "Fase atual" do `CLAUDE.md` para N+1.
   - Mostre ao Ricardo: o link do guia no GitHub
     (`https://github.com/d0gz/estantes/blob/main/docs/guias/fase-N.md`, válido depois que o commit
     chegar ao `main`) e os 3 temas principais do guia.
