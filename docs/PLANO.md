# Plano do projeto Estantes

Fonte da verdade para o Claude Code. Resume tudo o que foi decidido no planejamento
(conversas de 01 a 03/10/2026). Quando uma decisão mudar, atualize este arquivo **e**
registre o motivo em "Histórico de decisões", no fim.

## Objetivo

App iOS que espelha as estantes físicas da casa em estantes virtuais, adiciona livros
jurídicos por foto e permite **buscar por assunto** dentro dos livros já catalogados
(título, sumário com página, CDDir e categorias). O objetivo principal é **aprender** cada
camada, do repositório ao deploy; cada fase termina com um guia do subagente teacher.

O app funciona offline (Core Data), inclusive a busca. A internet só entra para identificar
um livro novo e, como reserva, para estruturar um sumário fotografado (Gemini).
A busca é só na biblioteca do usuário, sem consultar o catálogo do servidor.

## Arquitetura

```
iPhone (offline)                      Supabase (plano grátis)                Externos
┌───────────────────────┐   livro    ┌─────────────────────────────┐
│ Câmera + Vision       │   novo     │ RPC buscar_livro (Postgres)  │
│  código de barras     │──────────▶│  lexml_livros (83.612 livros)│
│  OCR capa + ficha     │            │  obras / edicoes (cache)     │
├───────────────────────┤            ├─────────────────────────────┤  falhou   ┌──────────────┐
│ SwiftUI + Core Data   │◀──────────▶│ Edge Functions               │─────────▶│ LexML /urn   │
│  Estante, Livro,      │            │  enriquecer-urn              │          │ Google Books │
│  Categoria, Sumário   │            │  identificar-livro (secrets) │          │ Gemini       │
│  busca local (BM25F)  │            │  estruturar-sumario          │          └──────────────┘
│  export/import JSON   │            └─────────────────────────────┘
└───────────────────────┘
```

## Arquitetura do código (decidida em 03/10)

**MVVM em camadas** (Clean pragmático), **structs no domínio**, Core Data escondido no repositório,
nomes do domínio em português e sufixos técnicos em inglês. No SwiftUI não há controller: a tela é
função do estado, e o ViewModel faz o papel que o controller tinha no MVC.

### Camadas — as dependências apontam para dentro

| Camada | Contém | Pode depender de |
| --- | --- | --- |
| **Dominio** | entidades (structs), regras puras, casos de uso, protocolos ("portas") | Foundation, e nada mais |
| **Dados** | Core Data, cliente Supabase, Vision, formato de exportação | Dominio |
| **Apresentacao** | Views SwiftUI + ViewModels (`ObservableObject`, `@MainActor`) | Dominio |
| **App** | ponto de entrada e montagem das dependências | todas |

```
ios/Estantes/
  App/              EstantesApp, Dependencias (montagem)
  Dominio/
    Entidades/      Livro, Estante, Categoria (+ CorCategoria), ItemSumario, Candidato, FichaExtraida
    Regras/         ISBN, ParserISBD, ParserSumario, Pontuacao, JaroWinkler, Normalizacao
    Busca/          Tokenizador, IndiceInvertido, BM25F, FiltroBusca, MotorDeBusca, ResultadoBusca
    CasosDeUso/     IdentificarLivro, ExportarBiblioteca, ImportarBiblioteca
    Portas/         BibliotecaRepositorio, CatalogoServico, OCRServico, LeitorCodigoBarras
  Dados/
    Persistencia/   PersistenceController, BibliotecaRepositorioCoreData (NSManagedObject <-> struct)
    Rede/           CatalogoSupabase
    Visao/          OCRVision, LeitorCodigoBarrasVision
    Exportacao/     BibliotecaExportadaV1 (Codable)
  Apresentacao/
    Inicio/  Busca/  Estante/  Livro/  Categorias/  Scanner/  Sumario/  Confirmacao/  Componentes/
ios/EstantesTests/
  Dominio/          testes puros e rápidos
  Dados/            Core Data em memória, ida e volta da exportação
  Apresentacao/     ViewModels com serviços falsos
```

### Regras práticas

- **Caso de uso só onde há orquestração real:** `IdentificarLivro`, `ExportarBiblioteca`,
  `ImportarBiblioteca`. Ações simples (renomear estante, apagar livro) vão do ViewModel direto ao repositório.
- **Um único ponto de conversão** `NSManagedObject` ↔ struct, dentro de `BibliotecaRepositorioCoreData`.
  Views e ViewModels nunca veem `NSManagedObject`. Sem `@FetchRequest`: o ViewModel recarrega o
  estado depois de cada alteração.
- **Injeção pelo `init`:** cada tipo recebe seus protocolos no inicializador; a montagem acontece só em
  `App/Dependencias`. Sem singletons espalhados.
- **`async/await`** nas portas; ViewModels com `@MainActor`.
- **Previews e testes** usam implementações falsas das portas (sem rede nem banco real).
- **Nomes:** domínio em português (`Estante`, `prateleira`, `IdentificarLivro`); sufixos e convenções do
  Swift em inglês (`ViewModel`, `View`), seguindo as Swift API Design Guidelines.
- **Busca no Domínio:** `Dominio/Busca/` só usa Foundation. O índice é montado em memória ao abrir o
  app, a partir do repositório; depois de cada alteração, o livro é removido e reindexado. A
  normalização reaproveita `Regras/Normalizacao`.
- **Cor sem SwiftUI no Domínio:** `CorCategoria` é um identificador (enum `String`); a Apresentação o
  converte num `Color` com os tons claro e escuro.
- **Fora do app:** Edge Functions com handler HTTP fino e lógica em módulos puros (`deno test`);
  SQL em `supabase/migrations/`; `data/` são ferramentas, fora desta arquitetura.

### Por que assim

- As partes mais ricas do app são algoritmos puros (ISBN, ISBD, Jaro-Winkler, pontuação): no Dominio,
  rodam em testes de milissegundos e servem ao conjunto de avaliação da Fase 3.
- Protocolos permitem trocar implementações: Supabase por um falso nos testes; Core Data por SwiftData
  no futuro, mexendo só no repositório.
- Descartados: MVC (padrão do UIKit); Clean "de livro" com um caso de uso por ação e conversores em
  todas as camadas (pesado para duas entidades); `NSManagedObject` direto nas telas (acopla as telas
  ao Core Data e dificulta testar).

## Ambiente (Fase 0)

- Mac: MacBook Pro 15" 2015, **macOS Monterey 12.7.x + Xcode 14.2 / Swift 5.7**.
- CI: GitHub Actions `macos-26` com **Xcode 26** (exigido pela Apple para envio).
- iPhone: `.ipa` sem assinatura gerado pela CI, instalado com **Sideloadly** + Apple ID grátis (vale 7 dias).
- Claude Code: roda **no próprio Mac** (Monterey; não é suportado oficialmente, mas funciona).
  Ferramentas: XcodeGen 2.46.0 (binário pronto; não reinstalar) e `gh` (PRs e acompanhamento da CI).
- Plano B, se o ciclo pela nuvem ficar lento: OCLP + macOS Sequoia + Xcode 26 no Mac.

### Regras para compilar nos dois Xcodes (críticas)

- iOS 16 mínimo; `SWIFT_VERSION = 5.0`.
- Proibido: SwiftData, `@Observable`, macro `#Preview`, Swift Testing, macros em geral,
  APIs iOS 17+ sem `if #available`.
- Usar: Core Data, `ObservableObject` + `@Published`, `PreviewProvider`, XCTest, `NavigationStack`.
- Projeto gerado pelo XcodeGen (`ios/project.yml`, `projectFormat: xcode14_0`).
  Nunca editar nem commitar `Estantes.xcodeproj`.

### Ciclo de trabalho

1. Claude Code cria uma branch e edita no Mac.
2. `./scripts/testar.sh` (`xcodegen generate` + `xcodebuild test` no simulador iPhone 14, iOS 16) antes de cada commit.
3. Commit → push → `gh pr create` → CI (Xcode 26) roda os testes no PR, acompanhada com `gh`.
4. Ricardo revisa e faz o merge.
5. iPhone: Actions → iOS → Run workflow → artefato `Estantes-ipa` → Sideloadly.

## Dados (Fase 1)

### O que o LexML tem

- Dataset: 7 acervos TinyDB `{"_default": {"1": {...}}}`, uma linha só cada; lidos em streaming
  com `ijson.kvitems(f, "_default")` (`data/extrair_livros_lexml.py`).
- **83.612 livros únicos** (29.005 repetidos, todos cópias idênticas pela chave `identifier`),
  de **1556 a 2017**. Livros mais novos só via Google Books.
- O dataset traz só título, ano, URN, identifier e às vezes descrição. **Não tem autor, ISBN nem editora.**
- A ficha completa está em `https://www.lexml.gov.br/urn/<URN>`: autor, CDDir (com hierarquia) e
  **todas as edições da obra**, cada uma com URN, edição/tiragem, imprenta, páginas, ISBN e bibliotecas.
  Leitor pronto e testado: `data/enriquecer_urn.py`.
- robots.txt: `/urn` permitido com **5 s entre pedidos**; `/busca/` proibido para automação.
- **Assuntos ficam fora** (só existem em `/busca/`). Usamos a **CDDir**.
  O assunto do livro chega por outras vias: CDDir, sumário e categorias do usuário.
- **24.118 livros têm `descricao`**: em **19.936** ela é o sumário (`Sumário: ...`, itens separados
  por ` -- `), que serve para pré-preencher o `ItemSumario` (Fase 4); em **4.182** é uma sinopse
  (`Resumo: ...`), e 1.749 destas também trazem um "Sumário" no meio do texto.
- Enriquecimento **sob demanda** (um pedido por livro escaneado), nunca em massa.
- Não fundir registros por título + ano: há 1.683 pares repetidos (ex.: vários "Direito penal" de 2009).
  Edições se agrupam pela ficha /urn (que lista as edições) e pelo ISBN.

### Esquema no Supabase

```sql
create extension if not exists pg_trgm  with schema extensions;
create extension if not exists unaccent with schema extensions;

create or replace function f_unaccent(text) returns text
language sql immutable parallel safe set search_path = '' as
$$ select extensions.unaccent('extensions.unaccent', $1) $$;

create table lexml_livros (            -- importado do CSV
  lexml_id     text primary key,
  urn          text not null unique,
  titulo       text,                   -- 2 registros sem título
  ano          smallint,
  descricao    text,
  outros_tipos text
);
create index lexml_livros_titulo_trgm
  on lexml_livros using gin (lower(f_unaccent(titulo)) extensions.gin_trgm_ops);

create table obras (                   -- enriquecimento sob demanda
  id               bigint generated always as identity primary key,
  titulo           text not null,
  autores          text[] not null default '{}',
  cddir            text,
  cddir_hierarquia jsonb,
  ficha            jsonb not null,     -- bruta, para reprocessar
  enriquecida_em   timestamptz not null default now()
);

create table edicoes (
  urn      text primary key,
  obra_id  bigint not null references obras(id) on delete cascade,
  edicao   text, ano smallint, editora text, local text, paginas text,
  isbn13   text[] not null default '{}'
);
create index edicoes_isbn13 on edicoes using gin (isbn13);
create index edicoes_obra on edicoes (obra_id);
```

- Extensões no schema `extensions`, não em `public`: é o padrão do Supabase (o linter do painel acusa
  extensão em `public`) e as funções delas ficam fora da API REST.
- **Migrations com `psql`**, sem o Supabase CLI nesta fase: arquivos em `supabase/migrations/` com o nome
  no padrão do CLI (`AAAAMMDDHHMMSS_nome.sql`), aplicados com `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f <arquivo>` (sem o
  `ON_ERROR_STOP`, um erro no meio desfaz a transação mas o `psql` termina como se tivesse dado certo).
  `SUPABASE_DB_URL` fica no `.env` (fora do Git) e usa o *Session pooler* (IPv4, porta 5432); a conexão
  direta só tem IPv6. O CLI entra na Fase 4, com as Edge Functions; o nome no padrão evita renomear.
- Importar `livros_lexml.csv` (CSV, UTF-8 com BOM, CRLF, cabeçalho) com
  `./data/importar_lexml.sh [caminho do CSV]`. O JSONL fica fora do banco. Usa `\copy` (o arquivo sai
  do Mac pela conexão): o `COPY` comum lê o disco do servidor e exige `pg_read_server_files`, que o
  `postgres` do Supabase não tem. Transação única; recusa rodar se a tabela já tiver linhas.
- O CSV tem 7 colunas (`lexml_id, urn, titulo, autores, ano, descricao, outros_tipos`), mas `lexml_livros`
  não tem `autores`: o dataset não traz autor (a coluna vem vazia) e os autores chegam pelo enriquecimento
  da /urn, em `obras`. Por isso o `\copy` vai para uma tabela temporária de staging com as 7 colunas, e um
  `insert ... select` leva só as 6 úteis. A importação é dado, não esquema: não é migration.
- RLS nas três tabelas: `select` para `anon` e `authenticated`; nenhuma política de escrita (só a
  service role escreve, e ela ignora o RLS).
- Grants explícitos: `revoke all` e `grant select` para `anon` e `authenticated`. O padrão do Supabase
  para tabelas criadas pelo `postgres` dá TRUNCATE ao `anon` e **não** dá SELECT. GRANT (pode usar a
  tabela?) e RLS (quais linhas?) são camadas independentes: ler exige as duas.
- **RPC `buscar_livro(p_texto, p_ano)`** (`security invoker`, `stable`, `search_path = ''`; execução só para
  `anon` e `authenticated`). Opção **(c″)**, decidida com medições em 08/10:
  - **Filtro** com o operador `%` (`similarity` ≥ `pg_trgm.similarity_threshold`, padrão 0,3) sobre
    `lower(f_unaccent(titulo))`, a mesma expressão do índice: o GIN entrega os candidatos (~0,1 s).
  - **Ordem**: média de `word_similarity` (o título do catálogo aparece dentro do texto lido?) e `similarity`
    (os dois textos inteiros se parecem?) ↓, `abs(ano - p_ano)` com `nulls last`, `lexml_id` (ordem estável).
    A coluna `media_similaridade` devolvida é essa média. A ordenação roda só sobre os candidatos do filtro, então
    pode usar funções sem índice.
  - Texto com menos de 3 caracteres devolve vazio sem varrer a tabela.
  - Medido com 7 "capas" (título + autor + edição): (a) `similarity` pura acertou 4 em 1º lugar, 2 em 2º/3º
    e perdeu 1; (c′) `word_similarity` e depois `similarity` acertou 6 em 1º e perdeu o mesmo; (c) `%` **ou**
    `<%` acertou os 7, mas o `OU` com `<%` (sem índice nessa direção) força Seq Scan: 2,9 s, no limite do
    `statement_timeout` do `anon`.
  - (c′) foi descartada ao testar **títulos curtos**, a entrada normal da Fase 3: para "Prisão preventiva",
    "Prisão" (`word_similarity` 1,0, `similarity` 0,44) passava à frente de "A Prisão Preventiva" (0,89).
    A média (c″) mantém os ganhos nas capas longas e devolve a ordem certa nos títulos curtos.
  - `EXPLAIN ANALYZE` ("prisao preventiva", dados em cache): com índice 87 ms (o GIN devolve 3.522 candidatos
    em 7 ms; o recheck na tabela descarta 3.494 e leva ~80 ms); sem índice 582–757 ms (Parallel Seq Scan nas
    83.612 linhas). O tempo cresce com a frequência dos termos: "direito penal brasileiro" gera 14.645 candidatos.
  - O caso perdido ("Teoria Geral do Processo" + 4 autores, nota 0,27) só se resolve mandando o título já
    extraído (Fase 3), não a capa inteira.
- Projeto grátis pausa após 7 dias sem uso: `supabase-keepalive.yml` faz ping 2x por semana, só com o
  cabeçalho `apikey` (serve para a chave `anon` legada e para a `sb_publishable_`, que não é JWT).
  Armadilha: o GitHub desativa workflows agendados após 60 dias sem commits no repositório.

### Checklist da Fase 1

- [x] Criar projeto Supabase
- [x] 1.2 Conexão por `psql` (`.env` com `SUPABASE_DB_URL`)
- [x] 1.3 `[eu escrevo]` Migration com o esquema acima (extensões, `f_unaccent`, tabelas, índices, RLS)
- [x] 1.4 Importar o CSV e conferir contagem (83.612)
- [x] 1.5 `[eu escrevo]` RPC `buscar_livro(texto, ano)`: top 10 títulos parecidos (sem acento), filtro
      pelo índice e ordem da opção (c″) abaixo; devolve também a `descricao` (usada no pré-preenchimento do sumário)
- [x] 1.6 Secrets `SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY` no GitHub (ativa o keepalive)
- [x] 1.7 `EXPLAIN ANALYZE` com e sem o índice trigram (exercício do teacher): 87 ms × 582–757 ms

## App (Fase 2)

### Modelo de dados no aparelho (Core Data)

| Entidade | Campos | Regras |
| --- | --- | --- |
| `Estante` | id (UUID), nome, criadaEm | `livros` com exclusão em cascata; a interface confirma quantos livros serão apagados e oferece movê-los |
| `Livro` | id (UUID), titulo, subtitulo, autores, editora, edicao, ano, isbn13, paginas, cddir, cddirCaminho, urn, origem (lexml, googlebooks, gemini, manual), prateleira, fotoCapa, adicionadoEm | `estante` obrigatória (a chave fica no livro); `itensSumario` em cascata; `categorias` muitos-para-muitos |
| `ItemSumario` | id (UUID), ordem, nivel, numeracao (opcional: "Capítulo II", "1.2.3"), titulo, pagina (opcional), origem (foto, lexml, gemini, manual) | pertence a um `Livro`; apagado junto com ele (cascata) |
| `Categoria` | id (UUID), nome (único, sem diferenciar maiúsculas/acentos), cor (identificador da paleta) | muitos-para-muitos com `Livro`; apagar a categoria = **nullify** (os livros só perdem a etiqueta) |

- **No Core Data** (2.2): classes escritas à mão com sufixo `MO` (`LivroMO`...), só em `Dados/Persistencia/`;
  opcionais numéricos como `NSNumber?`; `autores` numa String com um nome por linha; sumário sem relação
  ordenada (atributo `ordem`); a conversão MO ↔ struct fica toda em `Conversao.swift`.
  **Limitação conhecida:** cada operação usa um contexto de fundo novo e grava com "busca pelo id, senão cria";
  dois `salvar` simultâneos do mesmo id poderiam duplicar o registro. Os ViewModels `@MainActor` chamam um de
  cada vez; rever na 2.8 (importação), com um contexto único de escrita ou *uniqueness constraints*.
- **Prateleira**: etiqueta de texto livre do usuário ("2ª de cima", "caixa azul"); sugerir as
  etiquetas já usadas naquela estante.
- **cddir × cddirCaminho**: `cddir` é o código (filtro por prefixo); `cddirCaminho` são os níveis da
  hierarquia em texto (entram no índice). No Domínio é `[String]`; no Core Data, uma String com ` > `
  (evita um Transformable).
- **Categorias** são as etiquetas manuais de assunto (não há campo `assuntos` à parte). Paleta fixa de
  ~10 cores com contraste conferido nos modos claro e escuro; no Domínio a cor é um identificador.
- **Sumário**: só o texto é guardado, nunca as fotos.
- **Formato único do sumário**: toda origem (foto, LexML, Gemini, manual) grava o mesmo `ItemSumario`,
  com a numeração impressa em `numeracao`, separada do `titulo` (que fica limpo para a busca). A regra
  `ValidacaoSumario` (Domínio) vale para todas: nível ≥ 1; o nível sobe no máximo 1 em relação ao item
  anterior; título não vazio; página menor que a anterior gera aviso, não erro. A entrada manual é
  item a item (numeração, título, página, recuo ↑↓); colar texto fica para a Fase 3, com o parser.
- **Exportar/importar**: `.json` versionado `{"versao": 1, "categorias": [...], "estantes": [...]}`;
  cada livro leva `cddirCaminho`, `itensSumario` e os UUIDs das suas categorias. Via folha de
  compartilhar e seletor de arquivos; UUIDs permitem **mesclar** ou **substituir** (perguntar).
  Na mesclagem, categorias casam pelo UUID (nome igual com outro UUID é reaproveitado) e o sumário
  de um livro é substituído em bloco. É também o backup contra a expiração do Sideloadly.

### Busca na biblioteca

Só na biblioteca do usuário, no aparelho e offline. Tudo em `Dominio/Busca/`, com testes XCTest.

- **Normalização**: minúsculas, sem acento, sem palavras vazias (de, da, do, e, em, para...).
- **Índice invertido** em memória, montado ao abrir o app; atualizado livro a livro depois de cada alteração.
- **Ranking BM25F** por livro. Pesos por campo: título (maior), subtítulo, nomes de categoria,
  `cddirCaminho`, itens do sumário, autor (peso baixo). Cada campo tem o próprio fator de tamanho (`b`).
  As frequências do termo nos campos são multiplicadas pelos pesos e somadas **antes** da saturação (`k1`),
  e o IDF é calculado uma vez por termo, sobre o livro inteiro.
  - Descartado: somar um BM25 por campo. Um termo presente em vários campos satura várias vezes,
    e o livro ganha nota demais.
  - O item do sumário mostrado no resultado é o de melhor nota BM25 entre os itens daquele livro.
  - Pesos e parâmetros ficam em constantes. São ajustados com os testes.
- **Filtros** combináveis: autor, editora, faixa de anos, estante, prefixo de CDDir e categoria (chips coloridas).
- **Resultado**: livro · item do sumário · página · estante · prateleira.

### Interface

- Botão da câmera embaixo, centralizado.
- Estantes em grade; estado vazio com livros esmaecidos `#cbe8f5` e "+" azul-escuro (conferir contraste).
- Topo: último livro escaneado + campo de busca (`.searchable`): título, autor e assunto →
  "Livro · item do sumário, p. N · Estante X · prateleira". Com a busca ativa, aparecem os chips de filtro.
- Tela do livro: escolher categorias e adicionar/editar/reordenar itens do sumário à mão.
- Exportar/importar e a tela de categorias (criar, renomear, trocar cor, apagar com confirmação) num
  menu (⋯) no canto superior.

### Checklist da Fase 2

Ordem das tarefas: 2.1 entidades + porta ✅ · 2.2 Core Data ✅ · **2.3 normalização + motor de busca (próxima)** ·
2.4 telas principais · 2.5 categorias · 2.6 sumário manual · 2.7 busca na interface · 2.8 exportar/importar ·
2.9 fechamento (simulador + CI; Sideloadly adiado).

- [x] Entidades do Domínio (structs; `Livro` como agregado com o sumário; categorias por id; capa fora da struct) + porta `BibliotecaRepositorio` + regra do nome de categoria
- [x] `ValidacaoSumario` `[eu escrevo]` (escrita pelo Ricardo; 12 testes)
- [x] Modelo `Estantes.xcdatamodeld` (com `ItemSumario` e `Categoria`) + `PersistenceController` (com versão em memória) + `BibliotecaRepositorioCoreData` (conversão `[eu escrevo]` em parte; 25 testes de Dados)
- [ ] Tela inicial, estante → livros → detalhe, adição/edição manual, prateleira com sugestões
- [ ] Categorias: paleta com contraste conferido, tela de gerenciar, escolha na tela do livro
- [ ] Itens do sumário manuais na tela do livro (item a item, com `numeracao` e `ValidacaoSumario`)
- [ ] Motor de busca em `Dominio/Busca/` (normalização, índice invertido, BM25F `[eu escrevo]`, filtros) + testes
- [ ] Busca (título, autor, assunto) com filtros; exclusão com confirmação
- [ ] Exportar/importar (mesclar/substituir), com categorias e sumário + testes XCTest (exportar → importar → comparar)
- [ ] Simulador iOS 16 e CI verde (Sideloadly no iPhone adiado até haver aparelho)

## Identificação de livros e sumário (Fases 3 e 4)

### Ordem das fontes

1. **Código de barras** (EAN-13 = ISBN): `edicoes.isbn13` → senão Google Books.
2. **Extração algorítmica** → `buscar_livro` → pontuação → enriquecer a URN escolhida.
3. **Gemini** só quando nenhum candidato passa do limiar: estrutura o texto do OCR e a busca é refeita.
   Não inventa dados; sem confirmação, salva como "não verificado".
4. **Edição manual**, sempre disponível.

### Extração algorítmica

- Ficha catalográfica (ISBD): ` / ` separa título e autores; ` – ` antecede a edição;
  `Local : Editora, Ano`; `ISBN ...`. Parser por pontuação + regex.
- Regex de ISBN (com dígito verificador; ISBN-10 → 13) e ano.
- Capa: maior texto (altura da caixa do Vision) = candidato a título.
- Mandar a `buscar_livro` **só o título extraído**, nunca o texto inteiro da capa: autor e editora no texto
  derrubam a `similarity` abaixo do limiar (Fase 1, opção (c″)). Medir no conjunto de avaliação.
- NLTagger (`.personalName`) para autor; NLGazetteer com editoras jurídicas para editora.

### Pontuação

| Sinal | Peso | Comparação |
| --- | --- | --- |
| ISBN igual | decide | exato, dígito válido |
| Título | alto | trigramas, sem acento |
| Autor | médio | Jaro-Winkler após normalizar "Sobrenome, Nome" e iniciais |
| Ano, editora | desempate | igualdade/proximidade |

Buscar amplo (só título, ~10 candidatos), ordenar com todos os sinais. Alta: pré-seleciona.
Média: top 3 + "nenhum desses". Baixa: Gemini.

### Sumário

- **Captura**: `VNDocumentCameraViewController` (VisionKit, várias páginas) → `VNRecognizeTextRequest`.
  Etapa opcional depois da confirmação do livro e também na tela do livro. Só funciona no aparelho
  (no simulador, `isSupported` é falso); o parser é testado com texto, no Domínio.
- **Alternativa sem câmera**: `PhotosPicker` com várias páginas, sempre disponível (e a única no
  simulador). Fotos vão do Mac para o simulador arrastando para a janela ou com
  `xcrun simctl addmedia booted foto.jpg`.
- **Parser algorítmico** (`Regras/ParserSumario`): número no fim da linha = página; numeração
  (1., 1.1, I, a)) e recuo definem o nível e vão para `numeracao`; linhas quebradas são juntadas.
  A saída passa pela `ValidacaoSumario`, como a entrada manual.
- **Gemini como reserva** quando o parser falha (Edge Function `estruturar-sumario`).
- **Pré-preenchimento pela `descricao`** do LexML (`Sumário: ... -- ...`), com `origem = lexml`.
- Guarda só o texto, não as fotos.

### Avaliação (decide algoritmo × IA com números)

Conjunto de ~30 livros reais (fotos de capa + ficha) e **~10 sumários** com gabarito anotado à mão;
medir acerto por campo (livro) e por item/nível/página (sumário), do parser e do Gemini.

### Checklists

- Fase 3: câmera + `PhotosPicker`; conjunto de avaliação (livros + sumários); parser ISBD/regex/layout/
  NLTagger; script de medição; RPC + pontuação; tela de confirmação (candidatos, "nenhum desses", manual,
  estante sugerida pela CDDir, prateleira); cache local; scanner de sumário (VisionKit e `PhotosPicker`)
  + `ParserSumario` + avaliação. Fotos do conjunto de avaliação como recursos do alvo de testes
  (`EstantesTests/Recursos/`, no `project.yml`), com o OCR rodando em XCTest no simulador.
- Fase 4: Edge Functions `enriquecer-urn` (porta de `data/enriquecer_urn.py`, 5 s entre pedidos),
  `identificar-livro` (Google Books, Gemini) e `estruturar-sumario` (Gemini); chaves como secrets;
  limite de chamadas por dispositivo; pré-preenchimento do sumário pela `descricao`.

## Fases 5 e 6

- Fase 5: sinônimos jurídicos na busca (ex.: "CDC" ↔ "Código de Defesa do Consumidor"), navegação
  pela hierarquia da CDDir; foto da lombada das estantes, exportação com fotos (.zip), revisão de
  acessibilidade e modo escuro, ícone. CloudKit só se pagar o Developer Program.
- Fase 6: Sideloadly (grátis, 7 dias) é o padrão; TestFlight/App Store exigem US$ 99/ano.

## Aprendizado

- `teacher` (Sonnet): uma entrada por tarefa em `docs/aprendizado/fase-N.md`, com 3 perguntas;
  Ricardo responde por escrito e o teacher corrige na entrada seguinte.
- `teacher-consolidador` (Opus) + `/fechar-fase`: guia da fase em `docs/guias/fase-N.md`.
- `revisor` (Sonnet): revisa as tarefas marcadas `[eu escrevo]`, sem reescrever.

## Histórico de decisões

| Data | Decisão | Motivo |
| --- | --- | --- |
| 01/10 | Monterey + Xcode 14.2 local, Xcode 26 na CI; OCLP como plano B | Não mexer no macOS; App Store exige Xcode 26 |
| 01/10 | Core Data em vez de SwiftData | SwiftData exige iOS 17/Xcode 15 |
| 01/10 | XcodeGen | Claude cria arquivos sem editar o pbxproj; formato do Xcode 14 |
| 02/10 | Extrator TinyDB em streaming | Arquivos de até 5,6 GB numa linha só |
| 02/10 | Enriquecimento sob demanda pela /urn | Dataset sem autor/ISBN; robots.txt pede 5 s |
| 02/10 | CDDir em vez de Assuntos | Assuntos só em /busca/ (proibido) |
| 02/10 | Não fundir por título + ano | 1.683 pares repetidos de livros diferentes |
| 02/10 | CSV no banco, JSONL como arquivo bruto | JSONL não tem campo útil a mais |
| 03/10 | Ordem: ISBN → algoritmo → Gemini → manual | Exato e barato primeiro; IA não inventa |
| 03/10 | Chave da estante no `Livro` | Relação um-para-muitos |
| 03/10 | Prateleira = etiqueta livre | Achar o livro na biblioteca física |
| 03/10 | Busca + exportar/importar na Fase 2 | Objetivo do app; backup contra Sideloadly |
| 03/10 | MVVM em camadas, structs no domínio, nomes em português | Algoritmos testáveis sem simulador; telas independentes do Core Data |
| 03/10 | Claude Code no Mac (Monterey), com `./scripts/testar.sh` (xcodegen + xcodebuild test) antes de cada commit | Testa no Xcode 14.2 antes da CI; ciclo mais curto que pela web |
| 03/10 | Guias de fase só em Markdown (`docs/guias/fase-N.md`), sem PDF, Pandoc nem Typst | O Homebrew não funciona no macOS 12 (Tier 3) e compilaria GHC/LLVM/Rust do código-fonte; o GitHub já mostra o .md formatado, com Mermaid |
| 03/10 | Nova funcionalidade: busca por assunto nos livros catalogados; o fluxo do app não muda | Achar *onde* um tema é tratado nos livros que já se tem; título e autor não bastam |
| 03/10 | Busca só local e offline (índice invertido + BM25F no Domínio); nada de busca no catálogo do servidor | A biblioteca cabe em memória; funciona sem rede; algoritmo clássico testável em XCTest |
| 03/10 | Fontes de assunto: sumário (foto ou `descricao`), CDDir (código + caminho) e categorias | Assuntos do LexML seguem proibidos (`/busca/`); 24.118 `descricao` já trazem sumário |
| 03/10 | `Categoria` (UUID, nome, cor) muitos-para-muitos com nullify, no lugar de um campo `assuntos` | Etiqueta reutilizável, renomeável e filtrável; apagar não leva livros junto |
| 03/10 | Cor da categoria como identificador de paleta fixa, não hex | Cada cor tem tom claro e escuro; Domínio sem SwiftUI |
| 03/10 | Sumário fundido nas Fases 3 (scanner + parser) e 4 (Gemini + `descricao`); sinônimos e CDDir na 5 | Reaproveita câmera, Vision, conjunto de avaliação e Edge Functions sem atrasar a identificação |
| 03/10 | Sumário guarda só texto, não fotos | Menos espaço e exportação leve; o texto é o que a busca usa |
| 03/10 | Ranking BM25F (frequências ponderadas por campo e somadas antes da saturação) em vez de somar um BM25 por campo | Um termo presente em vários campos saturaria várias vezes e inflaria a nota; o BM25F é o padrão para documentos com campos |
| 07/10 | Migrations aplicadas com `psql`; Supabase CLI só na Fase 4 | `psql` já está no Mac; o CLI só é necessário para as Edge Functions |
| 07/10 | Extensões `pg_trgm` e `unaccent` no schema `extensions` | Padrão do Supabase; ficam fora da API REST |
| 07/10 | Importação por tabela de staging, em script fora das migrations | O CSV tem a coluna `autores` vazia que a tabela não tem; dado não é esquema |
| 07/10 | Grants explícitos (`revoke all` + `grant select`) além do RLS | O padrão do projeto não dava SELECT ao `anon` e dava TRUNCATE, que o RLS não controla |
| 07/10 | Correção: dos 24.118 livros com `descricao`, 19.936 trazem sumário e 4.182 trazem resumo | Contagem feita na importação; a linha de 03/10 contava toda `descricao` como sumário |
| 08/10 | `buscar_livro` na opção (c″): filtra com `%` (índice) e ordena pela média de `word_similarity` e `similarity`, depois ano e `lexml_id` | Mesmo custo da `similarity` pura e ordem melhor quando o OCR traz texto a mais; a (c′) (`word_similarity` primeiro) favorecia títulos curtos; a (c), com `OU <%`, perde o índice (2,9 s) |
| 08/10 | Keepalive com o secret `SUPABASE_PUBLISHABLE_KEY` só no cabeçalho `apikey`, falhando quando faltam secrets | O projeto usa a chave nova `sb_publishable_` (não é JWT); um ping que sai verde sem consultar o banco esconde a pausa do projeto |
| 08/10 | `ItemSumario.numeracao` separada do título + regra `ValidacaoSumario` para todas as origens | Sumário por foto e por escrita fica no mesmo formato; título limpo para a busca |
| 08/10 | Toda captura com alternativa `PhotosPicker` (inclusive o sumário); testes de fotos no simulador; Sideloadly adiado | Sem iPhone por enquanto; câmera e VisionKit não funcionam no simulador, Vision e `PhotosPicker` sim |
| 08/10 | Classes do Core Data à mão com sufixo `MO` (codegen Manual/None) | A geração automática criaria `Livro`, `Estante`... colidindo com as structs do Domínio e visíveis no app inteiro |
| 08/10 | `autores` no Core Data como String com um nome por linha (`\n`) | Nomes de autor têm vírgula ("Sobrenome, Nome"); evita Transformable |
| 08/10 | Sumário com atributo `ordem` em vez de relação ordenada (`NSOrderedSet`) | Mais simples de substituir em bloco; relação ordenada é frágil e não funciona com CloudKit |
| 08/10 | `ItemSumario` ganha `id` (UUID) no Core Data | A struct já tem `id`; sem ele a ida e volta não preserva a igualdade |
| 08/10 | `apagarEstante` com destino igual à própria estante lança `destinoInvalido`; ids inexistentes: apagar ignora, ler devolve vazio, gravar lança erro | Revisão da 2.2: o destino igual pulava o "mover" e a cascata apagava os livros |
