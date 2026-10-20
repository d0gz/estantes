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
    Entidades/      Livro, Estante, Categoria (+ CorCategoria), ItemSumario, Candidato, FichaExtraida, LinhaOCR
    Regras/         ISBN, ParserFichaCIP, ParserFolhaDeRosto, ParserSumario, NumeroRomano, Pontuacao, JaroWinkler, Normalizacao
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
| `Livro` | id (UUID), titulo, subtitulo, autores, colaboradores (`[Colaborador]`: nome + papel em texto livre, 2.5b), editora, local, edicao, ano, isbn13, paginas, cddir, cddirCaminho, urn, origem (lexml, googlebooks, gemini, manual), prateleira, fotoMiniatura (foto livre: capa, folha de rosto…; era `fotoCapa`), adicionadoEm; isbn13 sempre com 13 dígitos sem hífens, prefixo 978/979 e verificador válido (regra `ISBN`, 13/10: toda porta de entrada passa por ela); **obras em vários volumes (2.3b):** volume (Int?), volumeRotulo ("Tomo XLVIII", "Vol. 24"), parte, serie, artigosInicio/artigosFim (Int?, opcionais: "Arts. 1710-1779") | `estante` obrigatória (a chave fica no livro); `itensSumario` em cascata; `categorias` muitos-para-muitos |
| `ItemSumario` | id (UUID), ordem, nivel, numeracao (opcional: "Capítulo II", "1.2.3", "Art. 1.710", "§ 5.108"), titulo, pagina (opcional, **texto** desde a 2.3b: "245", "XI"), origem (foto, lexml, gemini, manual) | pertence a um `Livro`; apagado junto com ele (cascata) |
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
  item a item (2.6: tela de item com numeração, título, página e `Stepper` de nível; na lista, deslizar muda o nível e
  arrastar reordena; ver "Sumário" na seção Interface); colar texto fica para a Fase 3, com o parser.
- **Obras em vários volumes** (achado das fotos reais, 09/10): tratados e comentários vêm em tomos, cada
  um com folha de rosto própria ("Tomo XLVIII", "Arts. 1.710-1.779"). `volume` é o número (ordena e
  desempata no LexML); `volumeRotulo` é o texto impresso; `parte` é a divisão da obra, entre o título e o volume
  ("Parte Especial"), e `subtitulo` guarda a matéria impressa abaixo do volume ("Direito das Obrigações: …", 2.5b);
  os dois entram na busca; `serie` vem da ficha CIP; `artigosInicio/Fim` são opcionais. `edicao` continua texto
  e guarda também a reimpressão ("3.ª ed., 2.ª reimpr.").
- **Âncoras jurídicas no sumário**: "Art. 1.710" e "§ 5.108" vão em `numeracao` (sem campo `rotulo` à parte:
  cada item tem um só prefixo impresso). Os subitens numerados de um § viram filhos (nível + 1) com a mesma página.
- **Página como texto** (`pagina: String?`): há páginas em romanos (prefácio, introdução). Uma regra pura do
  Domínio converte romano/arábico em número; a `ValidacaoSumario` compara páginas só dentro da mesma
  sequência (passar de "XII" para "1" não gera aviso).
- **CDD e assuntos da ficha CIP não viram campos do `Livro`** (continua a decisão de 03/10: categorias no lugar
  de `assuntos`). Ficam na `FichaExtraida` e no gabarito; os assuntos viram sugestão de categorias na tela de
  confirmação (Fase 3).
- **Sem migração**: o modelo muda na 2.3b, antes das telas (2.4) e do export v1 (2.8); ainda não há dados
  gravados em aparelho, então o `.xcdatamodeld` é editado direto e o JSON v1 já nasce com os campos novos.
- **Exportar/importar**: `.json` versionado `{"versao": 1, "categorias": [...], "estantes": [...]}`;
  cada livro leva `cddirCaminho`, `itensSumario` e os UUIDs das suas categorias. Via folha de
  compartilhar e seletor de arquivos; UUIDs permitem **mesclar** ou **substituir** (perguntar).
  Na mesclagem, categorias casam pelo UUID (nome igual com outro UUID é reaproveitado) e o sumário
  de um livro é substituído em bloco. É também o backup contra a expiração do Sideloadly.

### Busca na biblioteca

Só na biblioteca do usuário, no aparelho e offline. Tudo em `Dominio/Busca/`, com testes XCTest.

- **Normalização**: minúsculas, sem acento, sem palavras vazias (de, da, do, e, em, para...).
  - **Plural (2.3i)**: regra mínima do português (`Singular`: oes→ao, ais→al, eis→el, ns→m, vogal+res→r, zes→z,
    vogal+s; exceções testadas), aplicada pelo `Tokenizador` no índice e na consulta. O texto gravado não muda. O índice
    guarda também as palavras como foram escritas, para o prefixo ("cautelare" → `cautelar`). RSLP descartado.
  - Ortografia antiga ("sôbre", "emprêsa", comum nos livros de 1950–1970) já casa com a atual: a remoção de
    acentos resolve. "art. 1.710" já vira `art 1710` (o ponto entre dígitos some no `Tokenizador`).
  - **Hífen (2.3b)**: entre letras é removido, no índice e na consulta ("sub-rogação" → `subrogacao`, igual a
    quem digita sem hífen); entre dígitos continua separando ("1.710-1.779" não pode virar um termo só).
- **Campos indexados (2.3b)**: a `numeracao` dos itens entra no campo `sumario` (para "art 1710" achar o item;
  números estruturais como "1.2.3" viram um ruído pequeno, aceito); `parte` entra no campo `subtitulo`.
  **Desde a 2.3i** também `volume`, `volumeRotulo` e as pontas de `artigosInicio/Fim` (no `subtitulo`; o intervalo
  inteiro ficaria como ruído — "art 1750 → volume XXIV" seria outro recurso, se o uso pedir).
- **Índice invertido** em memória, montado ao abrir o app; atualizado livro a livro depois de cada alteração.
  O índice grava os *nomes* das categorias: renomear ou apagar uma categoria reindexa os livros dela.
- **Ranking BM25F** por livro. Pesos por campo: título (maior), subtítulo, nomes de categoria,
  `cddirCaminho`, itens do sumário, autor (peso baixo). Cada campo tem o próprio fator de tamanho (`b`).
  As frequências do termo nos campos são multiplicadas pelos pesos e somadas **antes** da saturação (`k1`),
  e o IDF é calculado uma vez por termo, sobre o livro inteiro.
  - Descartado: somar um BM25 por campo. Um termo presente em vários campos satura várias vezes,
    e o livro ganha nota demais.
  - O item do sumário mostrado no resultado é o de melhor nota BM25 entre os itens daquele livro.
  - Pesos e parâmetros ficam em constantes (`ParametrosBM25F.padrao`), ajustados com um **conjunto de
    consultas de referência**: 20–30 fichas reais e 15–20 consultas, cada uma com o livro esperado,
    medidas num teste XCTest (top 1/top 3 e MRR). Mudar um peso mostra o efeito em todas as consultas
    de uma vez; o app (2.7) só confere a sensação de uso e sugere consultas novas para o conjunto.
  - **Conjunto de referência (passo 6, 09/10)**: em `EstantesTests/Dominio/Busca/Referencia/`, dados em Swift
    (22 fichas: os 4 livros fotografados + 18 do LexML em grupos de vizinhos; 19 consultas de ajuste e 6
    sondas). Métricas no alvo de testes, com empate pessimista. Linha de base: top 1 0,895 · MRR 0,939.
    Resultado: **só o peso do sumário mudou (1,0 → 0,5)** → top 1 0,947 · top 3 1,000 · MRR 0,965 · item
    certo 1,000. Os outros parâmetros não mudaram nenhuma consulta: ficam os de partida, sem validação.
    Pisos congelados em `testMetricasNaoCaemAbaixoDoPiso` (top 1 ≥ 0,94, top 3 = 1, MRR ≥ 0,96, item = 1).
  - **Sondas decididas (2.3i, 09/10)**: plural (regra mínima), volume/rótulo/artigos no índice, **correção de digitação**
    (Damerau–Levenshtein restrita contra o vocabulário, só para termo desconhecido só de letras com ≥ 5 letras: 1 erro
    até 8 letras, 2 a partir de 9; desempate por df e ordem alfabética) e **OU de reserva** (só quando a lista do E,
    já filtrada, fica vazia e há ≥ 2 termos; ordena por quantos termos o livro tem e depois pela nota). `buscar` devolve
    `RespostaBusca` (resultados, `modo`, `correcoes`); cada resultado traz `palavrasAusentes`. A tela (2.7) mostra a
    correção ("buscar exatamente" = `corrigir: false`), a faixa do OU e o `volumeRotulo` na linha.
    Cinco sondas viraram ajuste; a #22 ("tratado direito privado") continua sonda: é ambígua por natureza.
    Consultas novas, escritas antes de medir: #26–#30 (plural ao contrário, "tomo xlviii", OU, e duas de risco inverso
    do peso do sumário). **Peso do sumário 0,5 → 0,25**: o plural tirou a parte estrutural da #11 e as de risco inverso
    não pioraram. Resultado: 29 de ajuste, todas em 1º (top 1, top 3, MRR e item = 1,000); pisos top 1 ≥ 0,96, MRR ≥ 0,98.
- **Filtros** combináveis: autor, editora, faixa de anos, estante, prefixo de CDDir e categoria (chips coloridas).
- **Resultado**: livro · item do sumário · página · estante · prateleira.

### Interface

- Botão da câmera embaixo, centralizado.
- Estantes em grade; estado vazio com livros esmaecidos na cor `superficie` (`#AED3FC`), frase e um botão só (ver "Inicio" abaixo).
- Topo: último livro escaneado + botão com a aparência da barra de busca, que empurra a tela "Busca" (revisto em 20/10;
  antes `.searchable`, ver 2.7 no checklist): título, autor e assunto →
  "Livro · item do sumário, p. N · Estante X · prateleira". Com a busca ativa, aparecem os chips de filtro.
- Tela do livro: escolher categorias e adicionar/editar/reordenar itens do sumário à mão.
- Exportar/importar e a tela de categorias (criar, renomear, trocar cor, apagar com confirmação) num
  menu (⋯) no canto superior.

- **Fundamentos do estilo (Estilo 0, decididos em 12/10):**
  - Referências: Apple Books (disposição dos livros: capas protagonistas, serifa, transição capa → detalhe), Bevel (forma e
    movimento: cartões macios, molas), Goodreads (densidade de informação do Detalhe) e Shelf Life (simplicidade).
  - Cores por papel (60-30-10): branco `fundo`; `#AED3FC` `superficie`/seleção; azul `#0579B8` único
    `destaque` (4,7:1 no branco; matiz do `#0369A1`, longe do índigo das categorias). Sobre a `superficie` clara o texto é
    `.primary` (13,5:1) e o destaque só aparece como ícone ou forma (3,05:1 ≥ 3:1, WCAG 1.4.11, no piso: não clarear
    mais): nenhum azul vivo passa 4,5:1 sobre o `#AED3FC`. No escuro, `#AED3FC`
    vira destaque e a superfície, azul-marinho `#12305A` (branco sobre ele 13,2:1). `textoSecundario` próprio
    (`#4A5A62`/`#C9D6DC`): o `.secondary` do sistema reprova (3,4:1 no branco). O petróleo `#1F5F73` saiu (opaco, "triste").
  - Tipografia: SF na interface; New York (`design: .serif`) só em títulos de livros e estantes; tudo Dynamic Type.
  - Forma: cantos contínuos, raios 8/12/20; sem contornos (separação por cor e sombra leve; no escuro, elevação por cor).
  - Movimento: animações por mola com tokens nomeados; transições de entrada e saída em vez de aparecer seco; respeitar
    "Reduzir movimento".
  - "Vidro" (Liquid Glass) imitado no iOS 16 (`.ultraThinMaterial`, brilho claro fino na borda, pressão com mola) só nos
    elementos flutuantes (botão da câmera, barra de filtros); as barras do sistema ganham o vidro real sozinhas no `.ipa`
    da CI (Xcode 26) em iPhone com iOS 26. Ícone do vidro em `.primary` (o material segue o modo, não a capa; o azul
    sumia sobre capas); o azul só no véu ao tocar. Limite conhecido: contraste sobre o que está atrás não é testado.
  - Ação principal com `EstiloPrincipal` (fundo `destaque`, rótulo `sobreDestaque`), não `.borderedProminent`: esse
    pinta o rótulo sempre de branco, ilegível sobre o `#AED3FC` no escuro (visto no catálogo).
  - Categorias (2.5), chip "A": etiqueta (`tag`), contorno na cor viva, fundo pastel (cor a 15% sobre o cartão) e
    texto no tom escuro do mesmo matiz no claro (escurecido só até ~4,6:1; ex. amarelo `#876C00`); no escuro, texto e
    contorno na variante de alto contraste do sistema. Cores do sistema sem azul/ciano/teal, e rosa próprio `#FF2D92`
    (escuro `#FF7AC0`), porque o `systemPink` ficava a 14° do vermelho. Protótipo em `-captura EstiloCategorias`;
    na 2.5, tons fixos por cor com teste de contraste (inclusive o texto sobre o véu escuro) e ajuste do verde se preciso.
  - Texto e controles sobre a `superficie` vão em `.primary` (o tint global daria 3,05:1 no claro).
  - SF Symbols: `.symbolRenderingMode(.hierarchical)`; variante `.fill` só no estado selecionado; tamanho acompanha o texto; sem enum de ícones.
  - Capas × lombadas: resolvido na Estante (13/10) com lista e miniatura; ver "Estante" abaixo.

- **Inicio (estilo aprovado em 12/10, capturas 1.4–1.5; degraus do azul em `Inicio_1.3-t1…t4` e `Estilo_1.4-t1…t4`):** `CartaoDeEstante` em `Componentes/` (fundo `cartao` com
  `.sombraSuave()`, ícone `books.vertical.fill` no destaque, nome em serifa e contagem em `textoSecundario` presos à base,
  altura mínima 96); grade de 2 colunas, 1 nos tamanhos de texto de acessibilidade; pressão com mola (`EstiloCartao`,
  modificador `.pressao` comum ao vidro e ao principal); entrada e troca de estado com a mola `suave` (esmaecer e subir
  um pouco; só esmaecer com "Reduzir movimento"; sem cascata). Vazio no padrão da HIG: ilustração que só informa
  (lombadas, sem "+"), título, frase e **uma** ação (`EstiloPrincipal`); o "+" da barra some sem estantes e surge com o
  primeiro cartão. Variantes descartadas: duas ações (botão + "+" da barra) e só o "+" da barra (estilo Notas).

- **Estante (estilo aprovado em 13/10, capturas 1.0–1.1, via `/decidir`):** um cartão por prateleira (`ScrollView` +
  `LazyVStack`, fundo `cartao`, `.sombraSuave()`, `Raio.grande`), cabeçalho fora do cartão em SF semibold
  `textoSecundario` com a contagem ("Caixa azul · 2"; o VoiceOver lê "Caixa azul, 2 livros"). Linha: `MiniaturaDoLivro`
  2:3 (44 pt, cresce com o texto até 66 pt), título em serifa (`Fonte.tituloLivroNaLista`, até 3 linhas; inteiro nos
  tamanhos de acessibilidade), volume, autor · ano; sem seta; toque com véu do destaque sem encolher (`EstiloLinha`).
  Sem foto, a substituta: `superficie` com `book.closed` em `.primary`. A miniatura é a **foto livre** do livro
  (`fotoMiniatura`), lida por linha pelo `CarregadorDeMiniaturas` (ImageIO + `NSCache` com o tamanho guardado).
  Vazio igual ao Inicio ("Nenhum livro nesta estante", "Adicione os livros que ficam neste móvel.", "Adicionar
  livro"); o "+" da barra só com livros. Exemplos: duas fotos desenhadas em código (sem fotos reais). Descartados: grade
  de capas, lombadas, `List` restilizada, seta ›, miniatura de 56 pt. Os chips de categoria entram na 2.5 (abaixo).

- **Detalhe (estilo aprovado em 13/10, capturas 1.0–1.2, via `/decidir`):** `ScrollView` com cabeçalho centralizado
  (referência: Apple Books): `MiniaturaDoLivro` de 140 pt (`@ScaledMetric`, teto de 180 pt nos tamanhos de
  acessibilidade) com `.sombraSuave()`, título em `Fonte.tituloLivro`, subtítulo em `textoSecundario`, volume em
  semibold e a linha dos autores. **Autores no cabeçalho só pelos sobrenomes, como na ABNT (NBR 6023):** um autor,
  nome inteiro; 2–3, "Cintra, Grinover e Dinamarco"; 4 ou mais, "Sarlet et al."; sobrenome = o que vem antes da
  vírgula ("Sobrenome, Nome"), sem vírgula vai o nome inteiro. Depois, um cartão por seção (modificador `.cartao()`,
  comum a Inicio, Estante e Detalhe; título fora do cartão como na Estante): **Autor/Autores** primeiro (nomes
  inteiros, um por linha, sem rótulo), Obra (parte, número do volume quando há rótulo impresso, série, artigos),
  Publicação e Na estante; campos com rótulo pequeno (`.caption`, `textoSecundario`) em cima e valor embaixo.
  "Apagar livro" no fim, em cartão próprio, em `Cor.perigo` (vermelho de alto contraste da Apple, `#D70015`/`#FF6961`:
  o `systemRed` dá 3,6:1 no branco). Barra só com voltar e "Editar"; empurrão padrão com entrada pela mola `suave`.
  Sem espaço reservado para sumário (2.6) e categorias (2.5). Descartados: `List` restilizada, cabeçalho lado a
  lado, todos os autores com nome inteiro no cabeçalho (com texto grande a quebra dentro de um nome parecia outro
  autor), "e mais N" (soava traduzido), "+ N" (colide com o "+ Categoria" da 2.5), título na barra (pediria medir a
  rolagem à mão no iOS 16). Exemplos: na Sala, um livro com 3 autores e outro com 2 de nome longo (capturas
  `LivroDetalheTresAutores` e `LivroDetalheDoisAutores`).

- **Apagar estante (estilo aprovado em 13/10, capturas 1.1 claro, escuro e texto grande, via `/decidir`):** fica a
  folha de ação nativa (`confirmationDialog`) em duas etapas, com a opção que preserva os livros ("Mover os 6 livros e
  apagar…") antes da destrutiva; uma folha própria com cartões foi descartada (refazer posição, VoiceOver e iPad à mão
  para uma confirmação que deve ser rápida e familiar). Os botões de **todos** os alertas e folhas de ação do app usam
  o `destaque` (`Paleta.aplicarNoUIKit()`, proxy de aparência do `UIAlertController`, chamado no `init` do app): o
  `.tint` do SwiftUI não chega a eles no iOS 16, e o azul do sistema destoava do petróleo; o destrutivo continua
  vermelho. Título da segunda folha com a quantidade ("Mover os 6 livros para…", "Mover o livro para…"). Mantidos:
  aspas retas (`Apagar "Escritório"?`; as curvas foram recusadas pelo Ricardo) e destinos só com o nome (a
  quantidade pesaria a lista; o Inicio já a mostra).

- **Formulário (estilo aprovado em 13/10, confirmado em 16/10, capturas 1.2–1.3, via `/decidir`):** `Form` nativo com o cinza
  agrupado e os cartões brancos do sistema (no escuro, `#1C1C1E`/`#2C2C2E` dentro da folha). **Exceção ao Estilo 0**,
  a pedido do Ricardo: nem `fundo` nem `cartao`, porque branco sobre branco sem sombra (o `Form` não tem sombra por
  seção) apagava os cartões, e o `Form` dá prontos apagar/arrastar autores, foco e fuga do teclado. Dos tokens vêm só
  `textoSecundario` (nomes dos campos e títulos das seções), `Espaco` e a serifa do título. Campo vazio: nome e exemplo
  no placeholder ("Edição (ex.: 3.ª ed.)"); preenchido: o nome passa para cima, pequeno (`.caption`), entrando com a
  mola `suave` (resolve o "1965 sem dizer que é o ano"); escondido do VoiceOver, que lê o rótulo do `TextField`.
  Título digitado em serifa (`Fonte.tituloLivroNaLista`). Título e subtítulo quebram linha (`axis: .vertical`), mas o
  Return (ou texto colado com linhas) vira espaço e fecha o teclado; ao salvar, o `RascunhoLivro` junta espaços e
  quebras repetidos num espaço só (todos os campos de texto). Autor com placeholder "Sobrenome, Nome" (o formato de
  que o cabeçalho do Detalhe tira o sobrenome). Sugestões de prateleira (linhas ↳) e erros em `Cor.perigo` como na
  lógica. Descartados: ScrollView com `.cartao()` (refazer o comportamento do `Form` à mão), nome sempre em cima
  (poluía e dobrava a altura do Novo), nome à esquerda, fundo branco com linhas em `superficie`. Aviso esperado no
  Xcode 26: `onChange(of:)` de um parâmetro é deprecated no iOS 17, mas é a única forma que o Xcode 14.2 aceita.
  **Foto (13/10, capturas 2.0–2.3):** primeira seção, sem cartão (`.listRowBackground(Color.clear)`), com a
  `MolduraDaFoto` (a mesma moldura da `MiniaturaDoLivro`, extraída) de 72 pt (`@ScaledMetric`, teto 120; menor que no
  Detalhe, aqui é só para conferir). Sem foto, o botão "Adicionar foto" abre a fototeca direto; com foto, o `Menu`
  "Trocar foto" tem "Escolher outra foto" e "Remover foto" (destrutivo). `PhotosPicker` com
  `preferredItemEncoding: .current`: o padrão converte a foto cheia (HEIC → JPEG) antes de entregar, e no simulador
  essa conversão falha (`PAMediaConversionServiceErrorDomain` 2). Escolher outra foto enquanto a anterior reduz cancela
  a anterior (`.task(id:)`). Se só a foto falhar ao gravar: "O livro foi salvo, mas a foto não." (folha aberta; Salvar
  de novo atualiza o mesmo livro). Se a foto atual não abrir na edição, aviso "Não foi possível abrir a foto atual."

- **Categorias (2.5, decidido em 16/10 via `/decidir`, estilo aprovado nas capturas `EstiloCategorias_1.6–1.7`,
  `Categorias_0.1–0.2`, `LivroDetalhe_2.0`, `Estante_2.0–2.1`):**
  - Paleta de 10 (`vermelho, laranja, amarelo, verde, menta, indigo, roxo, rosa, marrom, cinza`) com hex fixos em
    `Paleta.categoria(_:)` (`Componentes/PaletaDeCategorias.swift`; ver Histórico de 16/10). Por cor: **viva** (contorno e
    ícone: no claro a cor do sistema, no escuro a variante de alto contraste), **texto** (no claro o matiz escurecido até
    ~4,6:1; no escuro o alto contraste) e **véu** (fundo, a 15% sobre o `cartao`: a cor do sistema **normal** de cada
    modo, não o alto contraste, como no protótipo aprovado). Exceção: o **índigo** no escuro tem texto `#8582FF` (o
    alto contraste `#7D7AFF` dava 4,3:1 sobre o véu; escolhido entre três na captura 1.6), contorno no `#7D7AFF`. O
    **cinza** (`#8E8E93`, texto claro `#636366`, escuro `#AEAEB2`) foi aprovado e congelado na captura 1.6.
    `PaletaTests` mede o texto do chip sobre o véu para todas as `CorCategoria.allCases`, nos dois modos, e congela os
    tons de texto do claro (fonte: as capturas). Cor gravada desconhecida (o "azul" antigo) vira cinza na leitura.
  - Componentes: `ChipDeCategoria` (com a variante fantasma "+ Categoria": `plus`, contorno tracejado em
    `textoSecundario`, sem véu) e o `FluxoDeChips` (`Layout`, iOS 16; conta das linhas pura e testada; alinhamento à
    esquerda ou centralizado) que quebra os chips em linhas; todos visíveis, sem "+N" (na busca da 2.7, os chips vão numa linha com rolagem horizontal: lá os resultados importam mais que os filtros; decidido em 20/10). Com texto
    grande os nomes não cortam letra a letra (captura `EstiloCategorias_1.7-textogrande`). `EstiloPressao` (encolhe e
    escurece ao tocar) em `Componentes/`, para a foto e os chips.
  - Gerenciar: menu ⋯ do Inicio (`ellipsis.circle`, à direita do "+"; por ora só "Categorias", visível também sem
    estantes) → tela **empurrada** (não folha: a de criar/editar abriria folha sobre folha) com a lista alfabética, o
    chip e a contagem ("3 livros", pela porta `quantidadeDeLivrosPorCategoria() -> [UUID: Int]`), em `List` sobre o
    cinza agrupado do sistema com a `.sombraSuave()` no cartão (exceção ao Estilo 0, como o Formulário). Uma folha só
    para criar e editar (nome, grade de círculos com anel em `.primary` e ✓ na escolhida e o nome da cor para o
    VoiceOver, prévia do chip); erro do `NomeDeCategoria` em `Cor.perigo` só depois de tentar salvar. **Apagar por três
    caminhos** que levam à mesma confirmação (quantos livros perdem a etiqueta; os livros ficam): deslizar a linha, menu
    de contexto (Editar, Apagar) e "Apagar categoria" no fim da folha de edição (o caminho visível; os outros são
    atalhos, como em Notas e Lembretes). A cor já vem sugerida: a menos usada, empate pela ordem da paleta
    (`CorSugerida`, `[eu escrevo]` com ajuda).
  - Escolha no livro: folha com todas as categorias (alfabética, ✓, sem busca; as marcadas não sobem), "Nova categoria"
    no fim (volta já marcada); vazio com frase + "Nova categoria". Grava no "OK"; "Cancelar" descarta.
    **Nota:** pode virar "grava a cada toque" (estilo Lembretes), se o uso pedir. "Nova categoria" abre a folha de criar
    **por cima** da de escolha (folha sobre folha, exceção ao motivo da tela empurrada: empurrar o formulário dentro da
    folha poria uma `NavigationStack` dentro da outra). **Limitação conhecida:** o "OK" grava o `Livro` inteiro lido ao
    abrir a folha; se o livro mudasse entre abrir e confirmar, a mudança se perderia (mesma família da limitação da 2.2;
    rever se surgir uma porta só para categorias).
  - Detalhe: chips centralizados no cabeçalho, abaixo dos autores (no lugar de um cartão com "Editar"); tocar abre a
    escolha; sem categoria, o chip fantasma. Estante: linha de chips abaixo de autor · ano, fantasma só sem categoria,
    toque nos chips e menu de contexto "Categorias…" abrem a mesma folha; VoiceOver lê a linha combinada e ganha a ação
    "Categorias…" (`accessibilityAction`). Nos tamanhos de acessibilidade, os chips da Estante saem da coluna ao lado da
    miniatura e ocupam a largura da linha ("Constitucional" quebrava no meio da palavra). O Formulário continua sem
    categorias.

- **Sumário (2.6, decidido em 20/10 via `/decidir`; estilo aprovado sem mudanças sobre as capturas `Sumario/*_0.1`):**
  - `ItemDoSumarioView` (`Apresentacao/Sumario/`), o mesmo no Detalhe, no sumário completo e na folha: recuo de 16 pt
    por nível (`@ScaledMetric`, para no 5º nível), numeração em negrito antes do título, página à direita em
    `textoSecundario` com algarismos de largura fixa; o VoiceOver lê "Nível 3. § 5.108 Conceito…. Página 3."; item
    ainda sem título aparece como "Sem título" em itálico e `textoSecundario` (só na folha, antes de salvar).
  - Detalhe: cartão "Sumário" depois dos grupos e antes de "Apagar livro", com os 10 primeiros itens
    (`previaDoSumario`), "Ver sumário completo (N)" (empurra a `SumarioCompletoView`, só leitura) e "Editar sumário";
    sem sumário, "Com o sumário, a busca acha os temas dentro do livro." e "Adicionar sumário". Ações no `destaque`.
  - Folha "Editar sumário" (título na barra: "Sumário", o conteúdo; "Editar sumário" é o botão do Detalhe; `List`
    agrupada nativa, como o Formulário): itens como botões com a seta desenhada (ver
    Histórico de 20/10), deslizar à direita "Diminuir/Aumentar nível" (só os que mudam algo), à esquerda "Apagar",
    arrastar para reordenar, menu de contexto "Inserir abaixo"/"Apagar" (não brigou com o arrastar no iOS 16); erro
    do item em `Cor.perigo` só depois de tentar salvar, com a contagem no topo; aviso de página sempre, em
    `textoSecundario` com triângulo. Com mudanças, arrastar para fechar fica bloqueado e "Cancelar" pergunta
    ("Descartar as alterações do sumário?", revisão P9: um sumário digitado à mão dá trabalho para refazer).
  - Tela de item (`EdicaoDoItemView`, `Form`): Numeração, Título (quebra linha; o Return passa à Página), Página
    (teclado `.numbersAndPunctuation`; o Return faz "Próximo item"), `Stepper` "Nível N" (até o anterior + 1, ou o nível
    atual se o item já passou disso: nada é corrigido sozinho) e
    "Próximo item" (desligado sem título), que troca de item sem navegar e mantém o teclado. Item sem nada escrito
    sai ao voltar.

- **Busca (2.7, decidido em 20/10 via `/decidir`; estilo E1–E4 sobre as capturas `Busca/*_1.0–1.1`, a aprovar no uso):**
  - Inicio: botão com a aparência da barra (lupa, "Título, autor ou assunto", `tertiarySystemFill`) numa pilha acima da
    lista (Q29), que empurra a tela "Busca" (título pequeno, "Cancelar" à direita, voltar escondido).
  - Cabeçalho fixo sobre os resultados (`safeAreaInset` + `.ultraThinMaterial` + fio embaixo): campo próprio e a
    linha horizontal de chips [Filtros (n)] [Categoria ▾] [estantes…]. Chip de filtro (E1): cápsula `tertiarySystemFill`
    desmarcado; `superficie` marcado, texto `.primary`, ✓ nas estantes e ícone `.fill` em "Filtros (n)".
  - Resultado: a `LinhaDoLivro` da Estante + chips de categoria (só leitura) + duas linhas (E3): item do sumário e
    página em `.primary` com `list.bullet.indent` (o motivo da busca) e estante · prateleira em `textoSecundario` com
    `books.vertical`; no OU, "sem: …" em `.caption`.
  - Avisos (E4): faixa com ícone, sem cartão — `wand.and.stars` na correção (com "Buscar exatamente" no `destaque`) e
    `text.magnifyingglass` no OU, em `textoSecundario`.
  - Tela Filtros: `Form` nativo empurrado (como o Formulário), anos com regra e erro em `Cor.perigo` no rodapé.

### Forma de trabalho nas telas (2.4 em diante)

- **Primeiro a lógica, depois o estilo.** A 2.4 faz todas as telas funcionarem com componentes nativos do SwiftUI, sem
  decisões visuais (2.4a montagem e tela inicial · 2.4b apagar estante com confirmação · 2.4c estante → livros (agrupados
  por prateleira) → detalhe · 2.4d adicionar/editar livro à mão · 2.4e prateleira com sugestões). Depois vem o estilo,
  **uma tela por vez** (Inicio → Estante → Detalhe → Formulário → Apagar estante), depois de um "Estilo 0" com os
  fundamentos comuns (tokens de cor, tipografia, espaçamento, forma; ver "Onde paramos"). A tela só fecha com a aprovação do Ricardo.
- **Estilo:** a direção é um app moderno, "smooth" e "seamless". A cada captura, o Claude traz de 2 a 4 perguntas de estilo
  numeradas, com opções e uma recomendação (cartões, cores, tipografia, animações, SF Symbols, modo escuro).
  O estilo comum fica em `Apresentacao/Componentes/` (cores, fontes, espaçamentos), e cada tela mantém
  identidade própria. As escolhas são registradas na seção Interface. Só APIs do iOS 16, sem `if #available`.
- **Capturas:** `docs/capturas/<Tela>/<Tela>_<versão>.png` (ex.: `Inicio/Inicio_1.2.png`), **só locais** (no `.gitignore`).
  Versão: o primeiro número é a rodada (0 = lógica, 1, 2… = estilo); o segundo, o ajuste dentro dela.
  Feitas com `xcodebuild build` + `xcrun simctl boot/install/launch` + `xcrun simctl io booted screenshot`. O `simctl`
  não toca na tela; para telas internas, o app aceita **só em DEBUG** o argumento `-captura <Tela>`, que abre a tela
  direto com dados de exemplo em memória (sem tocar no banco real).
- **Parada por limite de uso:** quando faltarem 5–8% do limite da sessão (o `/usage`), parar onde estiver, atualizar
  este PLANO (onde parou e qual o próximo passo), commitar e abrir o PR em rascunho (`gh pr create --draft`) se ainda
  não houver. Voltar só quando o uso reiniciar ou o Ricardo mandar. O Claude não enxerga o `/usage`: **o Ricardo avisa**.
  Commits pequenos ao fim de cada passo limitam a perda se o aviso não vier.
- **Idioma:** `developmentLanguage: pt-BR` e `CFBundleDevelopmentRegion: pt-BR` (Info.plist) no `project.yml`, para os
  textos do próprio sistema ("Voltar", "Cancelar", "Editar", folhas e alertas) saírem em português sem catálogo de
  tradução. O app é só em português; localizar em inglês fica fora do escopo.

### Checklist da Fase 2

Ordem das tarefas: 2.1 entidades + porta ✅ · 2.2 Core Data ✅ · 2.3 normalização + motor de busca (passos 1–6 e sondas ✅) ·
2.3b modelo de obras em vários volumes + índice ✅ · 2.4 telas principais · 2.5 categorias · 2.6 sumário manual · 2.7 busca na interface · 2.8 exportar/importar ·
2.9 fechamento (simulador + CI; Sideloadly adiado).

- [x] Entidades do Domínio (structs; `Livro` como agregado com o sumário; categorias por id; capa fora da struct) + porta `BibliotecaRepositorio` + regra do nome de categoria
- [x] `ValidacaoSumario` `[eu escrevo]` (escrita pelo Ricardo; 12 testes)
- [x] Modelo `Estantes.xcdatamodeld` (com `ItemSumario` e `Categoria`) + `PersistenceController` (com versão em memória) + `BibliotecaRepositorioCoreData` (conversão `[eu escrevo]` em parte; 25 testes de Dados)
- [x] Tela inicial, estante → livros → detalhe, adição/edição manual, prateleira com sugestões
  (2.4a montagem e tela inicial ✅ · 2.4b apagar estante ✅ · 2.4c estante → livros → detalhe ✅ · 2.4d formulário ✅ · 2.4e prateleira ✅ ·
  estilo tela por tela ✅ · fechamento ✅)
  **Onde paramos (16/10, branch `fase2/telas`, 361 testes):** 2.4 concluída. PR #23 pronto para revisão; o merge sai
  quando o Ricardo mandar. **Próximo: 2.5 (categorias)**, numa branch nova a partir do `main` depois do merge, começando
  pelo `/decidir`. Pendências do estilo que passam para a 2.5: promover o chip do catálogo a componente, chips com texto
  grande quebrando letra a letra (também na 2.7) e a lista de pares do `PaletaTests` (com as cores novas).
  Antes (13/10): estilo de todas as telas aprovado, fotos prontas. No Detalhe, a pedido do Ricardo, duas correções da lógica: o número do volume aparece no
  cartão Obra quando há rótulo impresso (antes não aparecia em lugar nenhum) e o ISBN passou a ser validado
  (regra `ISBN` no Domínio; teclado `.numbersAndPunctuation` no formulário, para o hífen e o "X").
  Antes (12/10): lógica da 2.4a–e pronta e aprovada no simulador.
  2.4d: `RascunhoLivro` (Domínio; tudo texto, autores em lista; obrigatórios título, ≥ 1 autor, editora e ano, só no
  formulário; números inteiros > 0 com ponto de milhar; a edição preserva o que o formulário não mostra) +
  `LivroFormularioView` em folha (asterisco nos obrigatórios, erros em vermelho só depois de tentar salvar, autores com
  adicionar/apagar/reordenar, "Volume e coleção" recolhível, seletor de estante). Capturas `FormularioNovo`/`FormularioEditar`
  abrem a folha de verdade via `FolhaPendente` (uma vez só, na tela pedida).
  2.4e: `SugestaoDePrateleira` (Domínio; grafias juntadas pela `Normalizacao.chave`, espaços arrumados; vazio → todas em
  ordem natural; começa-por antes de contém; some a igual ao digitado; até 5) + sugestões no formulário só com o campo
  em foco (`@FocusState`), relidas ao trocar de estante; falha na leitura não atrapalha o formulário.
  Próximos, nesta ordem, cada um começando pela explicação e esperando o OK (o Ricardo testa cada passo à mão):
  1. **Estilo 0 — fundamentos** (antes de qualquer tela; base: Human Interface Guidelines da Apple):
     a. ✅ Referências e direção (12/10, via `/decidir`): ver "Fundamentos do estilo" na seção Interface.
     b. ✅ Tokens (12/10) em `Apresentacao/Componentes/`: `Cor`/`Paleta` (`fundo`, `cartao`, `superficie`, `destaque`,
        `sobreDestaque`, `textoSecundario`; em código com `UIColor(claro:escuro:)`, não em catálogo de cores, para o hex
        aparecer na revisão e o teste medir cada modo), `Espaco` (4–24), `Raio` (8/12/20) + `.cantos(_:)`, `Fonte` (só as
        serifadas), `Animacao` (`suave`, `rapida`, `esmaecer`) + `.animacaoSuave(valor:)`, `.sombraSuave()`, `EstiloVidro`;
        `.tint(Cor.destaque)` na raiz (chega às folhas do SwiftUI; alertas e folhas de ação, do UIKit, recebem o
        `destaque` por `Paleta.aplicarNoUIKit()`, ver "Apagar estante" na seção Interface). `.secondary` do sistema reprovou (3,4:1 no branco) e virou
        `textoSecundario` próprio. `Contraste` (WCAG) e `PaletaTests` ficam no alvo de testes (o app não calcula contraste).
     c. ✅ Catálogo (12/10): `App/CatalogoDeEstilo.swift`, só em DEBUG, em duas páginas (`-captura Estilo` e
        `-captura EstiloTelas`; o `simctl` não rola a tela). Capturas `docs/capturas/Estilo/`: 1.0 (com candidatos
        `#0A5FD6`, `#2563EB`, `#0369A1` e o petróleo, escolhido `#0A5FD6`; revisto para `#0579B8` no Inicio), escuro e texto grande (argumento
        `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL`; o `simctl` do Xcode 14.2 não muda o
        tamanho do texto); 1.1 com o `EstiloPrincipal` e o vidro em `.primary`.
        Página de categorias (`-captura EstiloCategorias`): 1.2 cor padrão × alto contraste; 1.3 propostas A, B e alto
        contraste; 1.4/1.5 a A com rosa próprio (escolhida). Texto grande das três páginas na 1.2.
        Pendências para as telas (cada uma no seu passo de estilo):
        - ✅ Trocar `.secondary` por `Cor.textoSecundario` (Inicio, Estante, Detalhe e `MensagemDeErroView`).
        - Com texto grande, chips lado a lado quebram letra a letra (rolagem horizontal ou quebra de linha; busca).
        - Promover o chip do catálogo a componente em `Componentes/` (o cartão de estante já foi, no Inicio).
        Revisão adiada: lista de pares do `PaletaTests` à mão (revisitar com cor nova, na 2.5); ✅ tokens sem uso
        apagados ao fim do estilo (16/10: só o `Espaco.enorme`). O modificador de pressão foi extraído no Inicio (terceiro estilo de botão).
  2. **Estilo**, uma tela por vez: Inicio ✅ (12/10, ver "Inicio" na seção Interface; destaque claro revisto para
     `#0579B8`) → Estante ✅ (13/10, ver "Estante" na seção Interface) → Detalhe ✅ (13/10, ver "Detalhe" na seção
     Interface) → Formulário ✅ (13/10, confirmado em 16/10, ver "Formulário" na seção Interface) → foto da miniatura ✅
     (13/10) → foto ampliada no Detalhe ✅ (13/10) → Apagar estante ✅ (13/10, ver "Apagar estante" na
     seção Interface) → fechamento ✅ (16/10, passo 3);
     cada tela decide só a composição, sobre os fundamentos já aprovados.
     ✅ Campo preenchido perdia o nome (resolvido no Formulário: nome pequeno em cima com o campo preenchido).
     ✅ **Foto da miniatura (13/10):** `RedutorDeFoto` (`Componentes/`, ImageIO: lado maior 1200 px, JPEG 0,8; o
     `CarregadorDeMiniaturas` também reduz com ele); a foto fica no ViewModel e só é gravada no "Salvar", só se mudou
     ("Cancelar" descarta); depois a closure `fotoTrocada` (sem valor padrão: a montagem é obrigada a ligar) chama o
     `esquecer(livroId)` do carregador, que soma um em `trocas` (`@Published`) para as `MiniaturaDoLivro` relerem.
     Cabeçalho na seção Interface ("Formulário").
     ✅ **Foto ampliada no Detalhe (13/10, pedido do Ricardo, aprovada no simulador):** com foto, a miniatura do
     Detalhe vira botão ("Ampliar foto"; ao tocar, encolhe com a mola e fica a 85% de opacidade); sem foto, nada acontece
     (`CarregadorDeMiniaturas.temFoto`: com a miniatura no cache, não lê a porta; sem ela, lê sem guardar). Toque
     abre `FotoAmpliada.swift`: apresentada pelo UIKit (`.overFullScreen` + esmaecer; ver Histórico de 13/10) sobre
     preto a 88%, com o Detalhe de leve atrás. Zoom pela `UIScrollView` embrulhada (até 4×; duplo toque 2,5× no ponto
     e volta). Fecha pelo ✕ ou puxando, para baixo ou para cima, como no Fotos (a foto acompanha o dedo e o escuro
     some na proporção; fecha passados 120 pt ou num puxão rápido, senão volta com mola); com zoom, arrastar só anda
     pela foto. Imagem: a guardada inteira (1200 px), por `fotoInteira`, fora do cache (a grande no cache tomaria o
     lugar da miniatura).
     Nota: com "Caixa azul" e "caixa azul" na estante, a sugestão mostra "caixa azul" (ordem natural), e o grupo da
     estante, a grafia mais usada; podem diferir (a porta não traz contagem).
  3. ✅ Fechamento (16/10): revisão final da branch inteira com `revisor` e `revisor-spec`; aprovados e feitos: P1
     (`Quantidade.livros` em `Componentes/`, saiu da `InicioView`, de que a Estante dependia só para o plural), P2
     (`.alertaDeErro(_:)` no lugar de três cópias do mesmo alerta), P4 (`SecaoDoLivro` → `GrupoDeCampos`: "seção" é termo
     a evitar no GLOSSARY), E1 (este PLANO), E3 (idioma em "Forma de trabalho nas telas"). Recusados: P3 (generalizar o
     carregando/erro seria prematuro), P5 (as pastas `Confirmacao/` e `Scanner/` têm `.gitkeep` desde a Fase 0), P6 e E5
     (`Estante` `Hashable`, exigido pela navegação). CI verde, PR pronto, checklist e CLAUDE.md atualizados.
  Ferramentas: `./scripts/testar.sh` (com `TEST_RUNNER_RELATORIO=1` na frente, roda também o relatório `[referencia]`
  e a varredura `[varredura]` da busca, que fora disso ficam pulados; a saída fica no log); `./scripts/capturar.sh <Tela> <versão> [<pasta>]` (casos no enum `Captura`, `App/Exemplos.swift`);
  testar à mão com `xcrun simctl launch "iPhone 14" com.ricardo.estantes -captura Inicio` (exemplos em memória).
- [x] Categorias: paleta com contraste conferido, tela de gerenciar, escolha na tela do livro
  + chips no cartão do livro na Estante (linha abaixo de autor · ano): chip fantasma "+ Categoria" só nos livros sem
  categoria; tocar nos chips abre a escolha; menu de contexto "Categorias…" (decisão de 13/10)
  + pendências do estilo: chip do catálogo como componente, chips com texto grande, pares do `PaletaTests`
  **Onde paramos (16/10, branch `fase2/categorias`, 400 testes):** 2.5 concluída (passos 1 paleta + `PaletaTests` ✅ ·
  2 `ChipDeCategoria` + `FluxoDeChips` ✅ · 3 `CorSugerida` `[eu escrevo]` ✅ · 4 porta + gerenciar + menu ⋯ ✅ · 5 escolha
  + Detalhe ✅ · 6 Estante ✅ · 7 fechamento ✅). Pendências do estilo resolvidas: chip como componente, chips com texto
  grande (`EstiloCategorias_1.7-textogrande`, `Estante_2.1-textogrande`), pares do `PaletaTests` (laço em `allCases`).
  No meio, a correção da barra do Detalhe sem fundo ao rolar (ver Histórico de 16/10). Revisão final: aplicados P1, P3–P6,
  P8, P9 e E1–E11; recusados P2 (foto ampliada sem janela: só com tela na janela, testada à mão), P11 (laço da
  `CorSugerida` mantido), P12, P13. **Próximo: 2.6 (sumário manual)**, numa branch nova depois do merge, pelo `/decidir`.
  **Risco técnico (passo 6):** na Estante, os chips são um botão dentro do botão da linha (`NavigationLink`). Conferido à
  mão pelo Ricardo no **iOS 16** (chips abrem a escolha, o resto da linha abre o Detalhe, segurar mostra "Categorias…");
  no **iOS 26** ainda não (sem aparelho nem simulador 26 no Mac): conferir quando houver.
- [x] 2.5b (urgente, antes da 2.6) Conferência do modelo com o OCR do Gemini (livros 01 e 03), pelo `/decidir`:
  - A. Convenção: matéria no `subtitulo`, `parte` = divisão da obra (GLOSSARY: Parte, Subtítulo, Colaborador;
    comentários do `Livro`; dados do `RascunhoLivroTests`); `avaliacao/json_gemini/` no `.gitignore`.
  - B. `Livro.colaboradores: [Colaborador]`: `Colaborador.swift`; atributo no `.xcdatamodel` e `Conversao` (uma linha
    por colaborador, "papel⇥nome", separadores do texto viram espaço); nome no campo `.autores` do `IndiceInvertido`;
    `RascunhoLivro` (linha sem nome sai); seção no `LivroFormularioView`/VM (apagar e mover genéricos); cartão Autor
    no Detalhe com o papel como rótulo; exemplo do Lassalle e capturas.
  - C. PLANO: modelo, folha de rosto, `ParserFichaCIP`, gabarito (`colaboradores`, `cdu`), "Contrato de campos",
    Histórico; CLAUDE.md.
  Notas da revisão (recusados): uma linha só com papel some sem aviso no formulário (decisão testada, sem `Problema`
  novo); `ForEach` das listas do formulário identifica a linha pela posição (mesmo padrão dos autores) — dívida:
  id estável por linha se a perda de foco ao apagar/mover aparecer.
  **Onde paramos (16/10, branch `fase2/conferencia-modelo`, 408 testes):** 2.5b concluída (capturas
  `LivroDetalheColaborador_1.0`, `FormularioColaborador_1.0`, `LivroDetalhe_1.3`). **Próximo: 2.6**, numa branch nova
  depois do merge.
- [x] Itens do sumário manuais na tela do livro (item a item, com `numeracao` e `ValidacaoSumario`)
  **Decidido em 20/10 (`/decidir`, branch `fase2/sumario`):** Detalhe com cartão "Sumário" (depois dos grupos, antes de
  "Apagar livro") com os ~10 primeiros itens e "Ver sumário completo (N)" → tela empurrada; sem sumário, frase +
  "Adicionar sumário". Edição numa folha própria "Editar sumário" (Salvar grava o `Livro` inteiro; Cancelar descarta):
  a lista só mostra os itens; "Adicionar item" (no fim) ou tocar na linha empurra a tela de item (Numeração, Título,
  Página, `Stepper` de Nível de 1 até o anterior + 1) com "Próximo item" (guarda logo abaixo, limpa, mantém o nível e o
  foco no Título); deslizar dá "← Nível", "Nível →" e "Apagar"; segurar e arrastar reordena; menu de contexto "Inserir
  abaixo" e "Apagar" (o "Apagar" entrou na lógica, como atalho; se o menu brigasse com o arrastar no iOS 16, iria para o
  deslizar: não brigou). Regra pura `RascunhoSumario` no Domínio. Nada é
  corrigido sozinho: salto de nível é erro na linha e bloqueia o Salvar (mudar o nível não mexe nos filhos); erros só
  depois de tentar salvar, o aviso de página sempre, discreto. Sem `[eu escrevo]`. Lógica primeiro, estilo depois.
  Passos: 1 `RascunhoSumario` + testes ✅ (T1–T6, 432 testes; limpeza em `Normalizacao.textoLimpo`) · 2 lógica das telas ✅ (444 testes; roteiro aprovado no simulador em 20/10, inclusive menu de contexto × arrastar) · 3 estilo ✅ (aprovado sem mudanças em 20/10) · 4 fechamento ✅.
  Achado do passo 2 (20/10): no iOS 16, `navigationDestination(for:)` numa folha aberta de dentro da pilha principal põe
  o app em laço (CPU a 100%, Detalhe preso no "carregando"), também com um tipo próprio no lugar do `UUID`; a folha usa
  `navigationDestination(isPresented:)` e itens-botão com a seta desenhada (Histórico de 20/10).
  Revisão final: aplicados P1 (validação uma vez por mudança, num dicionário por id, em vez de uma por item a cada
  desenho), P2, P4–P10, P12 e E1–E5, E7; recusados P3 (`.onMove` sem modo de edição: conferido à mão no iOS 16) e P11
  (`RascunhoSumario.Item` repete o `ItemSumario`, como o `RascunhoLivro`). 449 testes.
  **Onde paramos (20/10, branch `fase2/sumario`, 449 testes):** 2.6 concluída; PR aberto. **Próximo: 2.7 (busca na
  interface)**, numa branch nova depois do merge, pelo `/decidir`.
- [x] Motor de busca em `Dominio/Busca/` (normalização, índice invertido, BM25F, filtros) + testes
  (passos da 2.3: 1 tokenizador ✅ · 2 índice invertido ✅ · 3 BM25F ✅ · 4 filtros ✅ · 5 motor e resultado ✅ ·
  6 conjunto de consultas de referência e ajuste dos pesos ✅, depois da 2.3b · 2.3i sondas: plural, volume/artigos,
  correção, OU de reserva, peso do sumário 0,25 ✅; 224 testes)
- [x] 2.3b Obras em vários volumes: campos novos do `Livro` (volume, volumeRotulo, parte, serie, local,
  artigosInicio/Fim); `pagina` como texto + regra de conversão romano/arábico (`NumeroDePagina`); `ValidacaoSumario`
  comparando por sequência (escrita pelo Claude, a pedido do Ricardo); Core Data + `Conversao.swift`; `numeracao`
  e `parte` no índice; hífen no `Tokenizador`; 171 testes
- [ ] Busca (título, autor, assunto) com filtros; ~~exclusão com confirmação~~ (já feita na 2.4: "Apagar livro" no Detalhe)
  **Decidido em 20/10 (`/decidir`, branch `fase2/busca-interface`):** índice mantido pela `BibliotecaIndexada`
  (`actor`, decorador do `BibliotecaRepositorio` em `Dominio/CasosDeUso/`; ver Histórico de 20/10): repassa cada
  chamada e, só depois de gravar com sucesso, atualiza o `MotorDeBusca` (`salvar(livro)` → atualizar; `apagarLivro` →
  remover; `apagarEstante` sem destino → remove os livros, com os ids lidos antes; com destino → relê os movidos;
  criar/renomear/apagar categoria → `atualizar(categorias:)` com a lista relida; renomear estante e foto → nada).
  `preparar()` idempotente, disparado ao abrir o app; `buscar` espera a montagem; falha → "Não foi possível preparar a
  busca." e nova tentativa na próxima busca. Tela: `.searchable` no Inicio, `ResultadosDaBuscaView` no lugar da grade
  com a busca ativa, `BuscaViewModel` próprio; busca a cada tecla com `.task(id:)` (cancela a anterior), sem espera.
  Linha: a da Estante + `LinhaDoResultado` ("§ 5.108 Conceito, p. 12 · Escritório · 2ª de cima", partes ausentes
  omitidas; "sem: stf" no OU); toque → Detalhe. Filtros: linha horizontal [Filtros (n)] [Categoria ▾] [estantes…];
  folha "Filtros" com autor, editora e anos; **CDDir sem interface** até haver dado (Fases 4/5).
  **Revisto em 20/10, depois do teste no simulador (Q17–Q20):** estantes continuam chips de seleção múltipla (só com
  2 ou mais estantes); categorias saem dos chips e vão para um `Menu` nativo "Categoria ▾" de **escolha única**
  ("Todas as categorias" desmarca; o chip mostra o nome escolhido), logo depois de "Filtros"; cada resultado mostra os
  chips de categoria do livro (só leitura, o toque abre o Detalhe; sem o fantasma "+ Categoria"). A folha "Filtros"
  mora na `InicioView`, fora da troca estantes ↔ resultados: presa aos resultados, fechava ao tocar num campo dela.
  **Revisto de novo em 20/10 (Q21–Q23):** "Filtros" é **tela empurrada** (`navigationDestination(isPresented:)` na
  `InicioView`), não folha: o log mostrou `isSearching = false` ao tocar num campo da folha, e no "OK" o Inicio voltava
  às estantes; empurrar, como o Detalhe, mantém a busca. Anos: só um ano de 4 dígitos filtra (`BuscaViewModel.ano`),
  para a lista não esvaziar a cada tecla; "De" depois de "Até" mostra "O ano inicial é depois do final." em
  `Cor.perigo`. **Editora fora da barra de busca** (só no filtro): seria um campo a mais no BM25F, sem algoritmo novo,
  mas traz ruído ("Livraria Freitas Bastos" casaria com o prefaciador Bastos do Lassalle; "Revista dos Tribunais"
  com "tribunais") e o peso não teria medida (só 4 das 22 fichas de referência têm editora).
  **Revisto de novo em 20/10 (Q25–Q28; revisa Q2 e a linha "Topo" da Interface):** a busca é uma **tela empurrada
  "Busca"** (`BuscaView`), não mais o `.searchable` do Inicio. O log mostrou que, no iOS 16, qualquer empurrão (Filtros
  ou Detalhe) desliga o `.searchable` da tela raiz, e ele volta inativo (sem "Cancelar"; com a barra vazia, os
  resultados sumiam). No Inicio, um botão com a aparência da barra (lupa, "Título, autor ou assunto"), sempre visível,
  empurra a "Busca". Lá: campo próprio (`TextField` + `@FocusState`, focado ao entrar; na volta de Filtros ou do
  Detalhe, o teclado não reabre), "Cancelar" à direita com o voltar escondido (volta às estantes e descarta a busca:
  o `BuscaViewModel` é criado a cada entrada), chips, resultados, Filtros e Detalhe empurrados de dentro dela.
  Descartados: `.searchable` dentro da tela Busca (o "Cancelar" continuaria sumindo na volta) e busca em folha com
  pilha própria (o laço do iOS 16 com `navigationDestination(for:)` numa folha, Histórico de 20/10).
  Vazio sem filtro: chips + "Busque por título, autor ou assunto"; só filtro: todos que passam. Avisos: "Mostrando
  resultados para **lassale**." + "Buscar exatamente "lassalle"" (`corrigir: false` até o texto mudar) e, no OU,
  "Nenhum livro tem todas as palavras. Mostrando os que têm parte delas." "Último livro escaneado" fica para a Fase 3.
  Sem `[eu escrevo]`. Lógica primeiro, estilo depois.
  Passos: 1 `BibliotecaIndexada` + testes + montagem ✅ · 2 `LinhaDoResultado` + testes ✅ · 3 `BuscaViewModel` +
  testes e telas ✅ (lógica aprovada no simulador em 20/10, depois das revisões Q17–Q29) · 4 estilo · 5 fechamento.
  **Onde paramos (20/10, branch `fase2/busca-interface`, 484 testes):** lógica aprovada; **próximo: passo 4 (estilo)**,
  com perguntas a cada captura (`Busca`, `BuscaCorrecao`, `BuscaOU`, `BuscaDica`, `BuscaFiltros`, `Inicio`).
  No caminho, o diagnóstico da rolagem na primeira entrada (Estante e Categorias; Histórico de 20/10). Q29: o botão de
  busca do Inicio fica numa pilha acima da lista (não `safeAreaInset`: ali o título grande passava sobre ele).
  Pendências do fechamento: tirar as capturas `docs/capturas/Diagnostico/` (locais), conferir o aviso de
  `onChange(of:)` da `FiltrosDaBuscaView` no Xcode 26.
- [ ] Exportar/importar (mesclar/substituir), com categorias e sumário + testes XCTest (exportar → importar → comparar)
- [ ] Simulador iOS 16 e CI verde (Sideloadly no iPhone adiado até haver aparelho)

## Identificação de livros e sumário (Fases 3 e 4)

### O que as fotos reais mostraram (09/10)

Fotos de 4 livros (`avaliacao/fotos/`, fora do Git): **nenhum tem ISBN**; 3 são de 1954–1972 e só têm
**folha de rosto** (sem ficha CIP); dois são tomos de obras em vários volumes. Os sumários usam âncoras
jurídicas ("§ 5.108.", "Art. 1.710 —"), páginas em romanos e às vezes o formato "Título, 5" sem pontilhado.
O plano anterior supunha ISBN/ficha na maioria dos livros e pedia a "contracapa".

### Ordem das fontes (ordem de confiança)

1. **Código de barras** (EAN-13 = ISBN): `edicoes.isbn13` → senão Google Books.
2. **Ficha CIP** (livros mais novos) → `ParserFichaCIP`.
3. **Folha de rosto** → `ParserFolhaDeRosto`. A captura pede "folha de rosto", não "contracapa".
4. **Capa** → maior texto = título.
5. Os passos 2–4 mandam o título extraído a `buscar_livro` → pontuação → enriquecer a URN escolhida.
6. **Gemini** só quando nenhum candidato passa do limiar: estrutura o texto do OCR e a busca é refeita.
   Não inventa dados; sem confirmação, salva como "não verificado".
7. **Edição manual**, sempre disponível.

### Extração algorítmica

Os parsers ficam no Domínio e recebem `[LinhaOCR]`: struct só com Foundation (texto, caixa com x/y/largura/
altura normalizados 0–1, confiança), montada em `Dados/Visao` a partir do Vision. Nada de `CGRect` ou
`VNRecognizedTextObservation` no Domínio; os testes usam o OCR gravado em JSON (ver Avaliação).

- **`ParserFichaCIP`**: cabeçalho "Sobrenome, Nome, datas"; "Título / responsabilidade" (depois do ";" vêm os
  colaboradores: "prefácio de Aurélio Wander Bastos"); "— Local: Editora,
  Ano"; série entre parênteses; assuntos numerados ("1. Direito civil"); CDD/CDU; ISBN. A coluna da esquerda
  (número de chamada, controle) é separada pela coordenada x.
- **`ParserFolhaDeRosto`** por geometria (altura da caixa ≈ tamanho da fonte; posição vertical):
  - título = as maiores linhas; autor = linha curta no topo ou depois de "por";
  - volume = (TOMO|VOLUME) + romano/arábico; edição = "N.ª EDIÇÃO" (+ REIMPRESSÃO);
  - ano = 4 dígitos no terço inferior; editora = Editor/Editora/Livraria/Ltda/S.A.; local = lista de cidades;
  - parte = texto de tamanho médio entre o título e o volume; subtítulo = matéria abaixo do volume (2.5b); entram na busca.
- **Capa**: maior texto (altura da caixa) = candidato a título.
- ISBN: reaproveitar `ISBN.normalizar` (`Dominio/Regras/ISBN.swift`, 13/10: dígito verificador, ISBN-10 → 13,
  prefixo 978/979, que já descarta o EAN de produto no código de barras); falta só achar o ISBN no texto (regex).
  Ano e conversão romano/arábico (regra da 2.3b, reaproveitada para volume e página).
- Mandar a `buscar_livro` **só o título extraído**, nunca o texto inteiro: autor e editora no texto
  derrubam a `similarity` abaixo do limiar (Fase 1, opção (c″)). Medir no conjunto de avaliação.
- NLTagger (`.personalName`) e NLGazetteer (editoras jurídicas) como apoio para autor e editora.

### Pontuação

| Sinal | Peso | Comparação |
| --- | --- | --- |
| ISBN igual | decide | exato, dígito válido |
| Título | alto | trigramas, sem acento |
| Autor | médio | Jaro-Winkler após normalizar "Sobrenome, Nome" e iniciais |
| Ano, editora | desempate | igualdade/proximidade |
| Volume, edição | desempate | títulos iguais de obras em vários volumes |

Conferir no `lexml_livros` como o LexML registra os volumes (no título? um registro por tomo?) antes de
fechar a pontuação. Buscar amplo (só título, ~10 candidatos), ordenar com todos os sinais. Alta: pré-seleciona.
Média: top 3 + "nenhum desses". Baixa: Gemini.

### Sumário

- **Captura**: `VNDocumentCameraViewController` (VisionKit, várias páginas) → `VNRecognizeTextRequest`.
  Etapa opcional depois da confirmação do livro e também na tela do livro. Só funciona no aparelho
  (no simulador, `isSupported` é falso); o parser é testado com texto, no Domínio.
- **Alternativa sem câmera**: `PhotosPicker` com várias páginas, sempre disponível (e a única no
  simulador). Fotos vão do Mac para o simulador arrastando para a janela ou com
  `xcrun simctl addmedia booted foto.jpg`.
- **Parser algorítmico** (`Regras/ParserSumario`) por **âncoras + geometria**, não por linha (uma entrada
  ocupa várias linhas e a página nem sempre fica na última):
  - números à direita (x > ~85% da largura) formam a coluna de páginas;
  - uma entrada começa em "§ N.NNN." / "Art. N.NNN —" / numeração (1., 1.1, I, a)) / recuo; a âncora vai para
    `numeracao`;
  - a página da entrada é o número da coluna cujo y cai dentro do bloco dela (às vezes vem uma linha antes do fim);
  - PARTE / CAPÍTULO / caixa alta / centralizado = níveis sem página;
  - formato "Título, 5" (sem pontilhado, com romanos) tratado à parte;
  - ruídos: cabeçalho corrido, fólio, transparência do verso (filtrar pela confiança), página curva;
  - colar texto (sem geometria) usa o mesmo parser, com cada linha numa caixa de largura inteira.
  A saída passa pela `ValidacaoSumario`, como a entrada manual.
- **Gemini como reserva** quando o parser falha (Edge Function `estruturar-sumario`).
- **Pré-preenchimento pela `descricao`** do LexML (`Sumário: ... -- ...`), com `origem = lexml`.
- Guarda só o texto, não as fotos.

### Avaliação (decide algoritmo × IA com números)

Conjunto de ~30 livros reais (capa, ficha CIP ou folha de rosto) e **~10 sumários** com gabarito anotado à
mão (hoje: 4 livros, 5 páginas de sumário); medir acerto por campo (livro) e por item/nível/página (sumário),
do parser e do Gemini.

- **Fotos** em `avaliacao/fotos/livro-0N-<nome>/` (`capa.jpg`, `ficha-cip.jpg`, `folha-rosto.jpg`,
  `sumario-0N.jpg`), **fora do Git** (direitos autorais e tamanho).
- **OCR em JSON**, no Git, em `avaliacao/ocr/`: gerado no Mac por um teste/script que roda o Vision nas fotos
  (texto, caixa, confiança de cada linha). Os parsers são testados com esse JSON, inclusive na CI, sem as fotos.
- **Gabarito** em `avaliacao/gabarito/livro-0N.json`, no Git:
  ```
  { "id", "fonte_identificacao",
    "livro": { "titulo", "subtitulo", "autores", "colaboradores": [ { "nome", "papel" } ], "editora", "local",
               "ano", "edicao", "reimpressao", "volume", "volume_rotulo", "parte", "serie", "isbn", "cdd", "cdu",
               "assuntos" },
    "sumario": [ { "ordem", "nivel", "rotulo", "titulo", "pagina" } ],
    "notas" }
  ```
  No gabarito, `rotulo` corresponde à `numeracao` do app; `reimpressao` fica separada para medir, mas no app
  vai junto em `edicao`; `cdd`, `cdu` e `assuntos` não têm campo no `Livro` (CDD e CDU com todos os códigos:
  "CDU 342 / 32" → `["342", "32"]`). Nos tomos, `subtitulo` é a matéria abaixo do volume.

### Contrato de campos (ficha CIP, folha de rosto, capa e sumário)

Conferido em 16/10 (2.5b) com o OCR do Gemini do livro 03 (tomo XLVIII) e do livro 01 (Lassalle, com ficha CIP),
contra as fotos. É a referência do que extrair, para o parser (Fase 3) e para o prompt do Gemini (Fase 4): o JSON
pedido usa estes nomes, e campo sem lugar aqui é lacuna do modelo, não do OCR.

| Impresso | Campo | Exemplo real |
| --- | --- | --- |
| Título | `titulo` | "Tratado de direito privado" |
| Matéria abaixo do volume, ou subtítulo | `subtitulo` | "Direito das Obrigações: Contrato coletivo do trabalho. …" |
| Autor(es) | `autores`, "Sobrenome, Nome" | "Miranda, Pontes de" |
| Prefácio, tradução, organização, coordenação | `colaboradores` (nome + papel) | `{nome: "Bastos, Aurélio Wander", papel: "prefácio"}` |
| Divisão da obra | `parte` | "Parte Especial" |
| Tomo/volume | `volume` + `volumeRotulo` | 48 + "Tomo XLVIII" |
| Artigos comentados | `artigosInicio/Fim` | 1710, 1779 |
| Coleção | `serie` | "Coleção estudos políticos constitucionais" |
| Edição e reimpressão | `edicao` | "3.ª ed., reimpr." |
| Editora, sem "Editor"/"Editora"/"Ltda." | `editora` | "Borsoi", "Liber Juris" |
| Cidade | `local` | "Rio de Janeiro" |
| Ano da edição (não o do copyright) | `ano` | 1972 |
| ISBN | `isbn13` (regra `ISBN`) | — |
| CDD, CDU, assuntos da ficha | `FichaExtraida` (fora do `Livro`) | CDD "320"; CDU "342", "32"; "Direito constitucional", "Ciência política" |
| Item do sumário | `ItemSumario`: `nivel`, `numeracao`, `titulo`, `pagina` (texto) | nível 3, "§ 5.108", "Conceito e natureza…", "3" |

Regras contra omissão:
- Texto inteiro, nunca cortado com "…".
- Página como texto, exatamente como impressa ("XI", "245"), nunca convertida em número.
- CDD e CDU com todos os códigos impressos ("CDU 342 / 32" → "342" e "32"), e todos os assuntos numerados da ficha.
- Editora sem a palavra de função ("Editor", "Editora", "Livraria") nem a razão social ("Ltda.", "S.A."):
  "EDITOR BORSOI" → "Borsoi"; "Editora Liber Juris Ltda." → "Liber Juris". É a única normalização; o resto vai como impresso.
- Subitens numerados de um § ("1. Conceito. 2. Figurantes coletivos.") viram filhos (nível + 1) com a mesma página.
- Divisões sem página (Parte, Capítulo) são itens com `pagina` vazia. Elementos pré-textuais (Nota explicativa,
  Prefácio, Introdução) são itens de nível 1 com a página impressa ("ix").
- Autor de um item do sumário fica no `titulo`, como impresso ("Prefácio [Aurélio Wander Bastos]").
- Fontes divergentes (CIP "Lassale" × capa "Lassalle"): transcrever a de maior confiança (ordem de 09/10) e
  devolver a outra como divergência, para a tela de confirmação (Fase 3).
- Fora, de propósito: cabeçalho corrido ("Tábua sistemática das matérias"), fólio, texto do verso, créditos
  (produção, capa), endereço da editora, ano do copyright, datas de vida do autor, números de controle e de chamada.

### Checklists

- Fase 3:
  - [ ] Script/teste local: Vision nas fotos → `avaliacao/ocr/*.json`
  - [ ] Gabaritos dos 4 livros já fotografados; ampliar até ~30 livros / ~10 sumários
  - [ ] `LinhaOCR` no Domínio + leitura do JSON nos testes
  - [ ] `ParserFichaCIP` + testes
  - [ ] `ParserFolhaDeRosto` (geometria) + testes
  - [ ] `ParserSumario` (âncoras + geometria) + testes
  - [ ] Script de medição (acerto por campo e por item/nível/página)
  - [ ] Conferir como o LexML registra volumes; RPC + pontuação com volume/edição/ano no desempate
  - [ ] Câmera + `PhotosPicker` pedindo capa, ficha CIP ou folha de rosto
  - [ ] Tela de confirmação (candidatos, "nenhum desses", manual, estante sugerida pela CDDir, prateleira,
        assuntos da CIP como sugestão de categorias); cache local
  - [ ] Scanner de sumário (VisionKit e `PhotosPicker`) + colar texto
- Fase 4: Edge Functions `enriquecer-urn` (porta de `data/enriquecer_urn.py`, 5 s entre pedidos),
  `identificar-livro` (Google Books, Gemini) e `estruturar-sumario` (Gemini); chaves como secrets;
  limite de chamadas por dispositivo; pré-preenchimento do sumário pela `descricao`.
  **Atenção (achado de 09/10):** no Supabase a `descricao` está cortada em 400 caracteres
  (`MAX_DESCRICAO_CSV` em `data/extrair_livros_lexml.py`; 10.145 de 24.118). O pré-preenchimento precisa da
  descrição inteira (reimportar a coluna ou ler a ficha `/urn`) e descartar o item cortado.
  O leitor do `/urn` às vezes devolve a hierarquia da CDDir repetida ("… > DIREITO PRIVADO > DIREITO CIVIL").

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
- `revisor-spec` (Sonnet): em paralelo com o `revisor`, compara o diff com o item do checklist e as
  decisões deste plano (o que faltou, o que sobrou, o que parece feito mas está errado).

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
| 09/10 | Pesos do BM25F ajustados por um conjunto de consultas de referência (passo 6 da 2.3, depois do motor), não testando o app | Uma métrica (top 1/top 3, MRR) mostra o efeito de cada ajuste em todas as consultas; no olho, consertar uma busca piora outras sem ninguém ver |
| 09/10 | Filtros (`FiltroBusca`): E entre dimensões, OU dentro de estantes e categorias; aplicados depois do BM25F; autor por palavras (prefixo, qualquer ordem, mesmo autor); livro sem ano/CDDir sai quando o filtro está ligado | Filtrar antes mudaria o IDF ao ligar uma chip; "contém" no texto inteiro não achava "José Afonso Silva" em "Silva, José Afonso da" |
| 09/10 | Ordem de confiança: código de barras → ficha CIP → folha de rosto → capa → Gemini → manual; a captura pede "folha de rosto" | Fotos de 4 livros reais: nenhum com ISBN, 3 (1954–1972) só com folha de rosto. Refina a ordem de 03/10 (o "algoritmo" vira três fontes), não a reverte |
| 09/10 | Parsers de ficha CIP, folha de rosto e sumário sobre `LinhaOCR` (texto + caixa + confiança), usando a geometria do Vision | Na folha de rosto o tamanho da fonte diz o que é título; no sumário a página fica numa coluna e nem sempre na última linha da entrada |
| 09/10 | `Livro` ganha volume, volumeRotulo, parte, serie, local e artigosInicio/Fim, numa tarefa 2.3b antes do passo 6 e da 2.4 | Obras em vários volumes; volume/ano/edição desempatam títulos iguais no LexML. Antes das telas e do export v1, sem dados gravados: sem migração |
| 09/10 | Âncoras ("Art. 1.710", "§ 5.108") em `numeracao`, que passa a ser indexada; sem campo `rotulo` | Cada item tem um só prefixo impresso; dois campos com o mesmo papel complicariam tela, Core Data e export. Ruído dos números estruturais é pequeno |
| 09/10 | `ItemSumario.pagina` como texto + valor numérico derivado; `ValidacaoSumario` compara por sequência | Páginas em romanos no prefácio; "XII" → "1" não é erro |
| 09/10 | Hífen entre letras removido no índice e na consulta; entre dígitos continua separando | "sub-rogação" = "subrogação"; "1.710-1.779" não pode virar um termo só |
| 09/10 | Fotos do conjunto de avaliação fora do Git; OCR gravado em JSON (`avaliacao/ocr/`) no Git | Direitos autorais e tamanho; a CI testa os parsers sem as fotos. Substitui "fotos como recursos do alvo de testes" |
| 09/10 | CDD e assuntos da ficha CIP fora do `Livro`; assuntos viram sugestão de categorias | Mantém a decisão de 03/10 (categorias no lugar de `assuntos`) |
| 09/10 | `NumeroDePagina`: romano só na forma canônica (conferida pela ida e volta inteiro → romano); num intervalo vale o início | A soma sozinha aceitaria lixo de OCR ("IIIII"); a ida e volta reaproveita a conversão em vez de uma regex |
| 09/10 | `ValidacaoSumario` compara a página só com a do item anterior com página, e só se for da mesma sequência; "s/n" é pulado | Comparar com o último da mesma sequência faria um índice remissivo em romanos no fim avisar contra o prefácio |
| 09/10 | Hífen entre letras: "-", U+2010 e U+2011 juntam; o travessão separa; o hífen invisível (U+00AD) some | Texto copiado e OCR trazem os hífens Unicode; o travessão é pontuação entre palavras |
| 09/10 | `parte` soma no campo `subtitulo` e `numeracao` no `sumario` (sem campos novos no BM25F); `volumeRotulo` e `serie` fora do índice | Mesmo papel, mesmo peso: um campo novo seria mais um peso a ajustar no passo 6. Revisitar se uma consulta de referência pedir |
| 09/10 | Conjunto de referência em Swift no alvo de testes (UUIDs fixos), não JSON; métricas também no alvo de testes, com empate pessimista | O `Livro` ainda muda até a 2.8: o compilador acusa campo renomeado. O app nunca calcula MRR. Empate decidido por título/UUID não é mérito de relevância |
| 09/10 | Peso do sumário no BM25F 1,0 → 0,5 (candidato A); o 0,25 (B) foi descartado | Conserta "processo penal" sem perder nenhuma consulta. O 0,25 só ganhava na "prisao caut" (caso misto, regra do prefixo), na ponta da grade, sem consulta que medisse o risco |
| 09/10 | Na varredura, o item certo é restrição (não se aceita troca que o piore); pisos congelados como teste de *snapshot* | `b` do sumário = 0 subia o MRR mas mostrava o item errado (o `notaDoItem` usa o mesmo `b`). Regra criada depois de ver o resultado, registrada como tal |
| 09/10 | Plural por regra mínima no `Tokenizador` (índice e consulta), com vocabulário de palavras escritas para o prefixo; RSLP descartado | "prisoes" não achava "prisão". O RSLP corta derivações e junta conceitos ("constitucional" × "constituição"); só o texto do índice muda, nunca o gravado |
| 09/10 | `volume`, `volumeRotulo` e pontas dos artigos no campo `subtitulo` | "tratado 48" e "arts 1710 1779" achavam nada; mesmo papel da `parte` (folha de rosto), sem peso novo. Revisa a linha de 09/10 que deixava `volumeRotulo` fora |
| 09/10 | Correção de digitação por distância de edição (OSA), só para termo desconhecido; trigramas descartados; não espera a Fase 5 | Termo desconhecido já daria lista vazia, então corrigir não muda consulta que funciona. Vocabulário pequeno dispensa índice de trigramas; a Fase 5 é de sinônimos |
| 09/10 | OU de reserva só com E vazio e ≥ 2 termos, ordenado por nível de coordenação; `RespostaBusca` com `modo`, `correcoes` e `palavrasAusentes` | Sem penalidade nem mistura com o E: as notas dos dois grupos não se comparam. A tela precisa explicar a lista |
| 09/10 | Peso do sumário 0,5 → 0,25 (revisa a linha de 09/10 que descartou o 0,25) | O plural tirou a parte estrutural da #11; duas consultas de risco inverso, escritas antes de medir, não pioraram. Continua na ponta da grade: não se estende a grade atrás de mais ganho |
| 09/10 | 2.4: primeiro a lógica de todas as telas (componentes nativos), depois o estilo tela por tela, com perguntas a cada captura | Garante o fluxo certo antes de gastar tempo com aparência; decidir o visual olhando cada tela no simulador |
| 09/10 | Capturas do simulador só locais (`docs/capturas/`, no `.gitignore`), com versão no nome; telas internas via argumento `-captura` só em DEBUG | Histórico visual sem pesar o repositório; o `simctl` não toca na tela |
| 09/10 | Lista da estante agrupada por prateleira; na 2.4 o Claude escreve tudo (sem `[eu escrevo]`) | Espelha a estante física; escolha do Ricardo |
| 10/10 | Formulário do livro: obrigatórios título, ao menos um autor, editora e ano (revisa "só título"); a exigência fica só no `RascunhoLivro`, não no `Livro` nem no Core Data | Escolha do Ricardo para fichas mais completas. LexML/Google Books/Gemini e livros antigos podem não ter esses dados: o modelo continua aceitando; editar um livro assim pede para completar |
| 10/10 | Autores no formulário como lista de campos (adicionar, deslizar para apagar, arrastar para reordenar); obrigatórios marcados com asterisco, sem nota de rodapé | Padrão do iOS (Contatos); separa os nomes sem depender do Return. Escolhas do Ricardo |
| 10/10 | Sugestão de prateleira por regra pura (`SugestaoDePrateleira`): chave normalizada, começa-por antes de contém, até 5; linhas-botão só com o campo em foco | Evita grafias diferentes da mesma etiqueta. `Tokenizador`/BM25F descartados (plural e correção confundem aqui); `Picker`/`Menu` não deixam criar etiqueta nova; `.searchSuggestions` só vale para `.searchable` |
| 10/10 | "Estilo 0 — fundamentos" antes do estilo tela por tela (complementa a linha de 09/10): referências, tokens semânticos (HIG), tela de catálogo em DEBUG, capturas claro/escuro | Decidir cor, tipo e espaçamento uma vez dá coerência entre as telas e encurta as perguntas de cada captura; modo escuro quase de graça. Escolha do Ricardo |
| 09/10 | Parada a 5–8% do limite de uso: PLANO atualizado, commit, PR em rascunho; volta só com uso reiniciado ou ordem do Ricardo | Não perder trabalho no meio; o Claude não vê o `/usage`, então o Ricardo avisa |
| 12/10 | Skills do Matt Pocock (MIT) adaptadas em português, não instaladas: `/decidir`, `revisor-spec`, cheiros de Fowler e regras de teste no `revisor`, `GLOSSARY.md`, `/diagnosticar`, hook de git em Python | O plugin vem em inglês, duplica PLANO, revisor, teacher e fechar-fase, supõe rastreador de issues e jq (ausente no Monterey); adaptar só as peças que faltam mantém um fluxo só |
| 12/10 | `auditor-testes` no `/fechar-fase` (só os testes alterados na fase); mutação manual (~10 mutações nas regras críticas, numa branch sem commit) a cada fase | O auditor lê o teste e acha esperado recalculado ou fraco; a mutação prova se algum teste percebe o código errado. 1ª rodada: 2 tautológicos e 14 fracos; 13/13 mutações mortas |
| 12/10 | Paleta por papel: branco `fundo` (60), `#AED3FC` `superficie` (30), petróleo `#1F5F73` único `destaque` (10); no escuro, `#AED3FC` vira destaque e o petróleo, superfície | Escolha do Ricardo a partir das referências; cores do sistema (azul padrão) descartadas por falta de identidade. `#AED3FC` sobre branco dá 1,55:1 e por isso nunca é texto; o petróleo dá 7,1:1 no branco e 2,4:1 no escuro, daí a troca de papéis |
| 12/10 | Fonte serifada (New York) só em títulos de livros e estantes; SF no resto, tudo Dynamic Type | Dá cara de livro (referência: Apple Books) sem perder a legibilidade dos controles; "só SF" e "serifa também nos títulos de tela" descartadas |
| 12/10 | "Vidro" (Liquid Glass) imitado no iOS 16 — material translúcido, brilho fino e pressão com mola — só nos elementos flutuantes; o vidro real fica com as barras do sistema no build da CI | `glassEffect`/`.buttonStyle(.glass)` são só iOS 26 e não compilam no Xcode 14.2; com `#if compiler` o efeito existiria só no `.ipa`, sem como ver ou testar. Vidro em tudo perde legibilidade sobre listas |
| 12/10 | Paleta de categorias = cores do sistema da Apple, sem azul/ciano/teal, em estilo pastel (fundo ~20%, texto padrão); implementada na 2.5 (complementa a linha de 03/10 da paleta fixa) | Tons claro/escuro e "Aumentar contraste" de graça; como texto sobre branco quase todas reprovam (amarelo 1,5:1), como fundo pastel passam (≥ 12,8:1). Pastel do Plotly descartado (hex fixos, sem modo escuro); azuis confundiriam com o destaque |
| 12/10 | Destaque claro azul vibrante `#0A5FD6` e superfície escura azul-marinho `#12305A` no lugar do petróleo; sobre a `superficie` clara, texto `.primary` e destaque só como ícone ou forma (≥ 3:1, WCAG 1.4.11) | Revisa a linha de 12/10 da paleta por papel: no catálogo o petróleo ficou opaco e "triste". O azul do sistema `#007AFF` reprova como texto no branco (4,0:1) e nenhum azul vibrante passa 4,5:1 sobre o `#AED3FC`, daí a regra da superfície. Escolhido olhando quatro candidatos no catálogo (`#2563EB`, `#0369A1` e o petróleo descartados) |
| 12/10 | Chip de categoria: etiqueta e contorno na cor viva, fundo pastel e texto no tom escuro do mesmo matiz (claro); alto contraste do sistema no escuro; rosa próprio `#FF2D92` no lugar do `systemPink` | Revisa a linha de 12/10 da paleta de categorias (pastel com texto padrão). Desenho do Ricardo; texto na cor viva reprova no branco (amarelo 1,5:1) e o alto contraste puro perdia a identidade pastel no claro. O fundo pastel e o contorno guardam a identidade, o texto escurecido passa 4,5:1. Fundo branco com texto preto (B) descartado por perder o texto na cor. `systemPink` (349°) se confundia com o vermelho (3°) |
| 12/10 | Destaque claro `#0579B8` (matiz do `#0369A1`, o mais claro que ainda dá 3:1 sobre o `#AED3FC`); o escuro segue `#AED3FC` | Revisa a linha de 12/10 do `#0A5FD6`: na barra de busca (2.7) os chips de filtro convivem com os de categoria, e o `#0A5FD6` ficava colado no índigo (ΔE 6 em OKLab; o `#0579B8`, 12). Escolhido entre 4 degraus de luz a partir do `#0369A1`; tirar o índigo das categorias foi descartado |
| 13/10 | Uma foto livre por livro (`fotoMiniatura`, renomeia `fotoCapa`), escolhida pelo usuário: capa, folha de rosto ou outra | Capas lisas não identificam o livro, e a folha de rosto (já pedida na captura, 09/10) sim. Duas fotos (capa + rosto) descartadas: mais dados no export e uma regra para escolher. O nome evita conflito com outras fotos que vão chegar |
| 13/10 | Tela Estante em lista com miniatura 2:3 em cartões por prateleira (resolve "capas × lombadas") | Títulos jurídicos longos e volumes ("Tomo XLVII") pedem texto horizontal; grade de capas descartada (sem fotos até a Fase 3 e sem autor/ano); lombadas descartadas (texto girado ruim com títulos longos e Dynamic Type) |
| 13/10 | Miniatura carregada por linha, reduzida com ImageIO e em cache em memória (com o tamanho guardado); no banco só a original | Miniatura gravada à parte descartada (dois campos em sincronia e uma dúvida no export); carregar a estante inteira descartado (200 fotos completas na memória) |
| 13/10 | Detalhe: cabeçalho centralizado (miniatura, título em serifa, volume e autores só pelos sobrenomes, como na ABNT: até 3, depois "et al.") e cartões por seção, com o cartão Autores listando os nomes completos | Com texto grande, a quebra dentro de um nome no cabeçalho se confundia com outro autor (vista nas capturas com 3 autores); "e mais N" soava traduzido e "+ N" colidiria com o "+ Categoria" da 2.5. List restilizada e cabeçalho lado a lado descartados |
| 13/10 | ISBN validado no Domínio (`ISBN.normalizar`): 10 ou 13 dígitos (hífens, inclusive Unicode, e espaços ignorados), "X" só no fim do ISBN-10, prefixo 978/979 e dígito verificador; guarda só os 13 dígitos (o ISBN-10 é convertido) | Antes aceitava letras. Livros anteriores a 2007 trazem ISBN-10; um formato só compara com código de barras e catálogos. Validar só quando o usuário muda o ISBN foi descartado: deixaria passar ISBN inválido de outra porta (como o "pede para completar" de 10/10). Sem o prefixo, o EAN de um produto passaria como livro na Fase 3 |
| 13/10 | Categoria no cartão do livro (2.5): chip fantasma "+ Categoria" só sem categoria, tocar nos chips abre a escolha, e o menu de contexto | Pedido do Ricardo. Um "+" em todo cartão foi descartado: alvo sobreposto ao link, 44 pt engordando cada linha, repetido em todas |
| 13/10 | Formulário no `Form` nativo com o cinza agrupado e os cartões brancos do sistema (pedido do Ricardo; só texto secundário, espaçamento e fonte vêm dos tokens), não ScrollView com `.cartao()` como no Detalhe (confirmado em 16/10) | O Detalhe é leitura; o formulário precisa de apagar/arrastar autores, foco e fuga do teclado, que o `Form` dá prontos. Refazê-los à mão foi descartado (mais código e risco por um raio de canto) |
| 13/10 | Foto do livro guardada reduzida (lado maior 1200 px, JPEG 0,8); a de alta qualidade só é usada (na Fase 3, o OCR roda na resolução máxima da câmera in-app) e depois descartada (confirmado em 16/10) | A original (3–10 MB) pesaria banco e export (200 livros ≈ 1 GB); 600 px borraria uma futura vista ampliada. Complementa a linha de 13/10 da miniatura (no banco só uma foto) |
| 13/10 | Foto ampliada do Detalhe apresentada pelo UIKit (`.overFullScreen` + esmaecer, num `UIViewControllerRepresentable` invisível), não por `fullScreenCover` nem por overlay | No iOS 16 o `fullScreenCover` é opaco (tira o Detalhe, e o fundo esmaecido precisa dele atrás) e o `presentationBackground` é do 16.4; overlay no Detalhe deixa a barra de navegação por cima do escuro, e na raiz do app espalha estado e uma ação pelo ambiente até uma tela funda |
| 16/10 | Formulário no `Form` nativo e foto guardada a 1200 px confirmados como definitivos | Revisa as duas linhas de 13/10 marcadas "provisório: a confirmar nas capturas": os dois foram vistos e aprovados nas capturas 1.2–2.3; manter o rótulo deixaria a dúvida aberta sem motivo |
| 16/10 | Paleta de categorias com 10 casos: vermelho, laranja, amarelo, verde, menta, índigo, roxo, rosa, marrom, cinza (saem azul e turquesa do enum de 03/10) | O enum ainda tinha azul e turquesa, vetados na linha de 12/10 (colidem com o destaque); as 9 vêm do protótipo aprovado (captura `EstiloCategorias_1.5`) e o cinza dá uma etiqueta neutra. O valor bruto vai para o Core Data e para o JSON v1, por isso muda agora, antes da 2.8. Só as 9, sem cinza, foi descartado |
| 16/10 | Apresentador da foto ampliada dentro do conteúdo rolável (no botão da miniatura) e como `UIViewRepresentable` que apresenta pelo topo da janela; revisa o detalhe de implementação da linha de 13/10 (continua UIKit com `.overFullScreen`) | No Detalhe, a barra de navegação não ganhava fundo ao rolar e o texto passava por baixo do "voltar". Causa (diagnosticada com captura rolada): uma vista do UIKit em volta da `ScrollView` (o `.background` na tela inteira) impede a barra de reconhecer a rolagem. Trocar só o `UIViewControllerRepresentable` por uma `UIView` não resolveu; o que resolveu foi a posição. Sem teste de regressão (sem XCUITest) |
| 16/10 | Tons das categorias congelados em hex (viva, texto claro, alto contraste escuro), lidos do iOS 16 em que foram aprovados, em vez de derivar das cores do sistema em tempo de execução | O `PaletaTests` roda no iOS 16 do Mac, mas o `.ipa` roda no iOS 26, cujas cores do sistema podem mudar: derivar deixaria o teste medindo outra cor que a da tela. Hex fixo aparece na revisão, como nos outros tokens |
| 16/10 | Nos tomos, a matéria impressa abaixo do volume ("Direito das Obrigações: …") vai no `subtitulo`; `parte` é a divisão da obra ("Parte Especial") | O OCR do Gemini (tomo XLVIII) e a folha do tomo I mostram três textos médios e o modelo não dizia onde ia a matéria (os testes divergiam). Campo novo descartado: mesmo papel na busca (já somam no `subtitulo`, linha de 09/10) e mais esquema antes do JSON v1. Juntar tudo em `parte` descartado: mistura dois dados. Refina a linha de 09/10 sobre `parte`/`subtitulo` |
| 16/10 | `Livro.colaboradores: [Colaborador]` (nome + papel em texto livre: prefácio, tradução, organização, coordenação); na busca, soma no campo de autores | A ficha CIP do Lassalle traz "prefácio de Aurélio Wander Bastos" e o modelo não tinha onde guardá-lo; em livro jurídico, coordenador e tradutor são procurados pelo nome. Juntar em `autores` descartado: o cabeçalho ABNT mostraria um prefaciador como autor. Enum de papéis descartado: o valor bruto ficaria congelado no JSON v1. `[String]` livre descartado: mistura nome e papel. Entra antes do JSON v1 (2.8), sem migração |
| 16/10 | CDU fica fora do `Livro`, ao lado da CDD, na `FichaExtraida` e no gabarito, com todos os códigos | O Gemini guardou só o "342" de "CDU 342 / 32". Estende a linha de 09/10 (CDD e assuntos fora do `Livro`), não a reverte |
| 20/10 | Sumário editado numa folha própria aberta pelo Detalhe, gravando o `Livro` inteiro no "Salvar"; não no formulário do livro nem gravando a cada mudança | O formulário ficaria enorme com centenas de itens e misturaria ficha e sumário; gravar a cada mudança tiraria o "Cancelar". Repete o fluxo da escolha de categorias (mesma limitação conhecida) |
| 20/10 | Editar um item do sumário preserva a `origem`; só o item novo é `manual` | O JSON v1 (2.8) congela o significado. Virar `manual` a cada correção apagaria o rastro de foto/LexML/Gemini que a avaliação do parser (Fase 3) usa |
| 20/10 | Na folha "Editar sumário", a tela de item é empurrada por `navigationDestination(isPresented:)`, com itens-botão e a seta desenhada; não por `navigationDestination(for:)` com caminho | No iOS 16, o destino por tipo numa folha aberta de dentro da pilha principal põe o app em laço (CPU a 100%, Detalhe preso no "carregando"), também com um tipo próprio no lugar do `UUID`. `NavigationLink(value:)` depende do destino por tipo; uma folha sobre a folha contrariaria a tela empurrada decidida para o item |
| 20/10 | Índice da busca mantido por um decorador `actor` do `BibliotecaRepositorio` (`BibliotecaIndexada`, no Domínio), que atualiza o `MotorDeBusca` só depois de cada gravação bem-sucedida; montado ao abrir o app | Um lugar só sabe o que muda o índice e se testa com o repositório em memória. Descartados: cada ViewModel avisar o índice (6+ lugares, fácil esquecer um), remontar a cada busca (relê o banco a cada tecla, contraria o PLANO) e classe `@MainActor` (busca na thread da interface e Domínio preso a ela) |
| 20/10 | Busca numa tela empurrada "Busca", com campo próprio (`TextField` + `@FocusState`) e "Cancelar"; no Inicio, só um botão com a aparência da barra. Revisa a decisão da manhã (`.searchable` no Inicio, resultados no lugar da grade) | No iOS 16, empurrar Filtros ou o Detalhe desliga o `.searchable` da tela raiz (visto no log) e ele volta inativo, sem "Cancelar"; remendos sobre o `isSearching` não seguravam os três casos. Descartados: `.searchable` dentro da tela Busca (o "Cancelar" continuaria sumindo) e busca em folha com pilha própria (laço do `navigationDestination(for:)` numa folha). Custo: o campo perde o vidro nativo do iOS 26 |
| 20/10 | Telas empurradas com título grande têm a rolagem (`ScrollView` ou `List`) na tela desde o primeiro quadro, com carregando, vazio e erro dentro dela (Estante) ou por cima dela (Categorias, que usa `List`) | Na primeira entrada na Estante e em Categorias, rolar não encolhia o título e a barra ficava sem fundo sobre a lista (vindo da 2.4/2.5, visto só agora). Causa, por laço de captura com rolagem por código (verde com ida e volta ao Detalhe, vermelho no `main` e na branch): o iOS escolhe a rolagem que a barra acompanha quando a tela aparece, e a lista só surgia depois do "carregando". Descartado: esconder o "carregando" (a leitura pode demorar no aparelho). Sem teste de regressão: só um XCUITest alcançaria a barra. Detalhe e Inicio passaram no mesmo laço |
