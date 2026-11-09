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

(sem respostas)

## Tarefa avulsa — Proteção contra segredos em permissões do Claude Code (2026-11-09)

### O que foi feito
Auditoria do repositório (público) após notícia sobre a pesquisa da Apiiro, e duas proteções preventivas: `.claude/settings.local.json` entrou no `.gitignore` e `Read(./.env)` entrou em `permissions.deny` no `.claude/settings.json`. A auditoria não achou nada exposto; não há credencial a trocar.

### Conceitos envolvidos
- **O vetor.** Ao escolher "Yes, and don't ask again" para um comando com credencial literal (ex.: uma senha dentro de uma URL), o comando inteiro vira regra `allow` em `.claude/settings.local.json`, em texto puro. Se esse arquivo for commitado num repositório público, o segredo é publicado. Não é CVE: é um fluxo de uso que mistura conveniência e persistência.
- **Exposto não é vazado.** Exposto = o segredo está num lugar acessível a quem não deveria. Vazado = alguém de fato o obteve. Você só pode provar a primeira; a segunda, em repositório público, deve ser presumida (há bots que varrem commits em segundos).
- **Rotacionar antes de limpar.** Se um dia vazar: primeiro invalide e troque a credencial; só depois limpe. Apagar do arquivo não apaga do histórico git, nem das cópias e forks já feitos. Reescrever histórico é higiene, não remédio.
- **Por que busca por formato não basta.** Gitleaks e TruffleHog procuram padrões (prefixos de chave, entropia). Uma senha de banco dentro de um comando comum não tem formato reconhecível; por isso 215 arquivos passaram. A auditoria aqui também foi por regex, então tem o mesmo limite.
- **`.gitignore` só afeta arquivos não rastreados.** Se o arquivo já estiver no índice do git, ignorá-lo não o remove (seria preciso `git rm --cached`). Aqui o arquivo nunca existiu no repositório, então a regra basta.
- **Defesa em profundidade.** Várias camadas imperfeitas somadas: `.gitignore` (impede o commit acidental), `deny` (impede a ferramenta de ler o `.env`), hábito (não aprovar segredo literal).

### Por que assim
- `.gitignore` do projeto, e não só exclude global: ele é versionado e vale em qualquer clone ou máquina. O exclude global da Apple/Claude Code fica só na máquina que o configurou.
- `Read(./.env)` com caminho exato: bloqueia o `.env` real sem bloquear `.env.example`, que só tem placeholders e é útil ao assistente.
- Preferir `psql "$SUPABASE_DB_URL"`: só o nome da variável fica salvo na regra; o valor continua no ambiente.

### Alternativas descartadas
- Confiar só no exclude global: não acompanha o projeto.
- `Read(./.env*)`: pegaria o `.env.example` junto.
- Scanner de segredos na CI: útil, mas com o limite de formato descrito acima; fica como possível extra.

### Padrões e boas práticas
Menor privilégio e defesa em profundidade; segredos no ambiente, nunca em argumentos de comando; rotação como resposta padrão a qualquer suspeita. Não confie em nenhuma camada sozinha.

### Armadilhas
- `deny` em `Read` não barra `cat .env` pelo Bash: é redução de risco, não barreira. Só o hábito e o ambiente separam o segredo do comando.
- O `.gitignore` não protege arquivo já rastreado: confira com `git ls-files .claude`.
- Reautorizações antigas (`~/.claude.json`, por projeto) ficam fora do repositório, mas valem uma olhada periódica.

### Para ir além
- Documentação do Claude Code: seção de permissões e `settings` (`permissions.allow/deny`).
- GitHub Docs: "Removing sensitive data from a repository" (e por que se rotaciona primeiro).

### Perguntas
1. Com suas palavras: qual a diferença entre segredo "exposto" e "vazado", e por que isso muda a ordem "rotacionar, depois limpar"?
2. Se amanhã um `settings.local.json` com senha já tivesse sido commitado, o `.gitignore` resolveria? Que passos, em ordem, você daria?
3. Por que o `deny` em `Read(./.env)` não impede um `cat .env` via Bash, e o que você faria para cobrir essa lacuna?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->
