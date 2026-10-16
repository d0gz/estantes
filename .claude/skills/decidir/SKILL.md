---
name: decidir
description: Sessão de perguntas em rodadas para fechar as decisões de uma tarefa ou assunto antes de agir, terminando com as linhas propostas para o "Histórico de decisões" do PLANO.md. Use quando o Ricardo digitar /decidir <assunto>.
argument-hint: "<assunto, ex.: 2.4 telas principais>"
disable-model-invocation: true
---

<!--
Adaptado de skills/productivity/grilling/SKILL.md e skills/engineering/domain-modeling/ADR-FORMAT.md,
do repositório "skills" de Matt Pocock (https://github.com/mattpocock/skills).
Copyright (c) 2026 Matt Pocock — licença MIT. Tradução e adaptação para o projeto Estantes.
-->

# Decidir: $ARGUMENTS

Entreviste o Ricardo até chegarem a um entendimento comum sobre **$ARGUMENTS**. Se o argumento vier
vazio, pergunte o assunto e pare.

## 1. Contexto (antes da primeira pergunta)

Leia, sem perguntar nada:
- a seção do `docs/PLANO.md` ligada ao assunto (e o item do checklist, se for uma tarefa);
- o "Histórico de decisões" do PLANO;
- o `GLOSSARY.md`, para usar os termos do domínio nas perguntas;
- o código que o assunto toca, só o necessário.

## 2. Árvore de decisões e rodadas

Monte a decisão como uma **árvore**: cada decisão abre as que dependem dela. A **fronteira** é o
conjunto das decisões cujas pré-condições já estão resolvidas, ou seja, as perguntas que dá para
fazer *agora* sem adivinhar respostas que ainda não vieram.

Trabalhe em **rodadas**: pergunte a fronteira inteira de uma vez, numere as perguntas, dê a sua
resposta recomendada e espere. Formato:

```
❓ **Q1** — **<título>**: <pergunta, com as alternativas reais e o custo de cada uma>

➡️ <resposta recomendada, com o motivo em uma linha>

---

❓ **Q2** — ...
```

- Escreva cada pergunta de modo que **"sim" aceite a recomendação**.
- Uma pergunta que depende de outra ainda aberta na mesma rodada fica para a rodada seguinte.
- A cada rodada respondida, recalcule a fronteira e faça a próxima.
- Se uma pergunta reabre uma linha do "Histórico de decisões", diga isso e cite a linha (data e
  decisão) antes da recomendação.

## 3. Fatos x decisões

- **Fatos são trabalho seu**, nunca do Ricardo: o que o código faz, o que o PLANO diz, o que o banco
  devolve (`psql`), o estado da CI (`gh`). Busque você mesmo, com leitura pontual; não abra subagente
  só para isso.
- Não trave a rodada por causa de um fato: só as perguntas que dependem dele esperam; as outras vão já.
- **Decisões são do Ricardo**: leve cada uma a ele e espere a resposta.

## 4. Fim

A sessão termina quando a fronteira fica vazia: todo ramo visitado, nada assumido em silêncio.
**Não aja** (não edite código nem o PLANO) até o Ricardo confirmar que o entendimento é comum.

Depois da confirmação, proponha as linhas para o "Histórico de decisões", no formato da tabela:

```
| DD/MM | <decisão> | <motivo, com a alternativa descartada> |
```

Uma decisão só entra se passar nos **três** critérios:
1. **Difícil de reverter**: mudar de ideia depois custa caro.
2. **Surpreendente sem contexto**: quem ler o código depois vai perguntar "por que assim?".
3. **Fruto de alternativas reais**: havia outras opções e esta foi escolhida por motivos claros.

Liste à parte as decisões que ficaram de fora, cada uma com o critério que faltou (elas vão no
checklist da tarefa ou em lugar nenhum). Se uma linha nova revisa outra, escreva "revisa a linha de
DD/MM" no motivo. Grave no PLANO só depois do OK do Ricardo.
