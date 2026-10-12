---
name: diagnosticar
description: Laço de diagnóstico para bugs difíceis e regressões de desempenho — primeiro um sinal de falha rápido e confiável, depois hipóteses, instrumentação, correção com teste de regressão e limpeza. Use quando o Ricardo pedir para diagnosticar/depurar, ou relatar algo quebrado, falhando, travando ou lento.
---

<!--
Adaptado de skills/engineering/diagnosing-bugs/SKILL.md, do repositório "skills" de Matt Pocock
(https://github.com/mattpocock/skills).
Copyright (c) 2026 Matt Pocock — licença MIT. Tradução e adaptação (enxuta) para o projeto Estantes.
-->

# Diagnosticar

Disciplina para bugs difíceis. Só pule uma fase com justificativa explícita. Leia o `GLOSSARY.md` e
as decisões do `docs/PLANO.md` da área afetada. Continua valendo "explique antes de fazer".

**Segredos:** nunca mostre chaves do Supabase, do Gemini ou do Google Books em comandos e saídas;
escreva `<REDACTED>` e use variáveis de ambiente.

## Fase 1 — Laço de feedback (é aqui que está o trabalho)

Com um sinal de passa/falha que fica **vermelho neste bug**, a causa aparece; sem ele, ler código não
resolve. Formas, mais ou menos nesta ordem:
1. **Teste XCTest que falha** na fronteira que alcança o bug, rodado com `./scripts/testar.sh`.
2. **Script Python** com entrada fixa (dados de `data/`, rodado com `python3 -I`), comparando a saída
   com uma saída boa conhecida.
3. **`psql`** contra o Supabase, para SQL e a RPC `buscar_livro`.
4. **Reprodução de um registro capturado**: salve em disco a entrada real (OCR em JSON, linha do
   LexML) e passe-a isolada pelo caminho do código.
5. **Laço de diferença**: a mesma entrada em dois commits ou duas configurações, comparando as saídas.
6. **`git bisect run`**, quando o bug surgiu entre dois estados conhecidos.
7. **Captura no simulador** (`xcrun simctl io booted screenshot`) para o que só aparece na tela.
8. Último recurso: pedir ao Ricardo que reproduza no simulador e cole a saída ou a captura.

Depois **aperte** o laço: mais rápido (menos passos e dados; o `testar.sh` roda a suíte inteira, então um script
fora do simulador vale quando o bug é de regra pura), sinal mais preciso
(conferir o sintoma exato, não "não travou") e determinístico (data fixa, semente fixa).
Bug intermitente: o objetivo é aumentar a taxa de reprodução (repetir 100×, forçar o tempo).

**Pronto quando** houver **um comando** já rodado (mostre a chamada e a saída) que: segue o caminho
real do bug e confere o sintoma que o Ricardo descreveu; dá o mesmo veredito a cada execução; leva
segundos; roda sem ninguém. Sem esse comando, não formule hipóteses. Se não der para montar o laço,
diga isso, liste o que tentou e peça ao Ricardo acesso, um registro capturado ou licença para
instrumentar.

## Fase 2 — Reproduzir e minimizar

Confirme que a falha é a que o Ricardo descreveu (bug errado = correção errada) e que se repete.
Encolha o cenário cortando entradas, passos e dados **um de cada vez**, rodando o laço depois de cada
corte, até que tudo o que sobrou seja necessário.

## Fase 3 — Hipóteses

Gere **3 a 5 hipóteses ordenadas** antes de testar qualquer uma. Cada uma precisa ser refutável:
"Se a causa é X, mudar Y faz o bug sumir / mudar Z piora". Mostre a lista ao Ricardo antes de testar
(ele pode reordenar ou descartar), mas não trave esperando.

## Fase 4 — Instrumentar

Cada sonda testa uma previsão da Fase 3; **mude uma variável por vez**. Prefira o depurador (`lldb`)
a logs; logs só nas fronteiras que separam as hipóteses, nunca "logar tudo". Marque todo log de
depuração com um prefixo único, ex. `[DEBUG-a4f2]`, para a limpeza ser um `grep`.
**Desempenho:** meça antes de mexer (XCTest `measure`, `EXPLAIN ANALYZE` no Postgres) e depois bisseccione.

## Fase 5 — Correção e teste de regressão

Escreva o teste de regressão **antes** da correção, se houver uma fronteira certa: uma que reproduz o
bug como ele acontece de verdade. Se só houver fronteira rasa demais, isso é um achado: registre que a
arquitetura impede travar o bug com um teste. Com a fronteira certa: transforme a reprodução mínima
num teste que falha → veja falhar → corrija → veja passar → rode de novo o laço da Fase 1 no cenário
original.

## Fase 6 — Limpeza

- [ ] A reprodução original não reproduz mais (laço da Fase 1 de novo)
- [ ] O teste de regressão passa (ou a falta de fronteira está registrada)
- [ ] Nenhum `[DEBUG-...]` sobrou (`grep` pelo prefixo)
- [ ] Protótipos descartáveis apagados
- [ ] A hipótese certa está na mensagem do commit, para quem depurar depois
