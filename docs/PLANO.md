# Plano do projeto Estantes

Fonte da verdade para o Claude Code. Resume tudo o que foi decidido no planejamento
(conversas de 01 a 03/10/2026). Quando uma decisão mudar, atualize este arquivo **e**
registre o motivo em "Histórico de decisões", no fim.

## Objetivo

App iOS que espelha as estantes físicas da casa em estantes virtuais e adiciona livros
jurídicos por foto. O objetivo principal é **aprender** cada camada, do repositório ao
deploy; cada fase termina com um guia do subagente teacher.

O app funciona offline (Core Data). A internet só entra para identificar um livro novo.

## Arquitetura

```
iPhone (offline)                      Supabase (plano grátis)                Externos
┌───────────────────────┐   livro    ┌─────────────────────────────┐
│ Câmera + Vision       │   novo     │ RPC buscar_livro (Postgres)  │
│  código de barras     │──────────▶│  lexml_livros (83.612 livros)│
│  OCR capa + ficha     │            │  obras / edicoes (cache)     │
├───────────────────────┤            ├─────────────────────────────┤  falhou   ┌──────────────┐
│ SwiftUI + Core Data   │◀──────────▶│ Edge Functions               │─────────▶│ LexML /urn   │
│  Estante, Livro       │            │  enriquecer-urn              │          │ Google Books │
│  export/import JSON   │            │  identificar-livro (secrets) │          │ Gemini       │
└───────────────────────┘            └─────────────────────────────┘          └──────────────┘
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
    Entidades/      Livro, Estante, Candidato, FichaExtraida
    Regras/         ISBN, ParserISBD, Pontuacao, JaroWinkler, Normalizacao
    CasosDeUso/     IdentificarLivro, ExportarBiblioteca, ImportarBiblioteca
    Portas/         BibliotecaRepositorio, CatalogoServico, OCRServico, LeitorCodigoBarras
  Dados/
    Persistencia/   PersistenceController, BibliotecaRepositorioCoreData (NSManagedObject <-> struct)
    Rede/           CatalogoSupabase
    Visao/          OCRVision, LeitorCodigoBarrasVision
    Exportacao/     BibliotecaExportadaV1 (Codable)
  Apresentacao/
    Inicio/  Estante/  Scanner/  Confirmacao/  Componentes/
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
- Enriquecimento **sob demanda** (um pedido por livro escaneado), nunca em massa.
- Não fundir registros por título + ano: há 1.683 pares repetidos (ex.: vários "Direito penal" de 2009).
  Edições se agrupam pela ficha /urn (que lista as edições) e pelo ISBN.

### Esquema no Supabase

```sql
create extension if not exists pg_trgm;
create extension if not exists unaccent;

create or replace function f_unaccent(text) returns text
language sql immutable parallel safe as
$$ select public.unaccent('public.unaccent', $1) $$;

create table lexml_livros (            -- importado do CSV
  lexml_id     text primary key,
  urn          text not null unique,
  titulo       text,                   -- 2 registros sem título
  ano          smallint,
  descricao    text,
  outros_tipos text
);
create index lexml_livros_titulo_trgm
  on lexml_livros using gin (lower(f_unaccent(titulo)) gin_trgm_ops);

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

- Importar `livros_lexml.csv` com `COPY` (CSV, UTF-8 com BOM, cabeçalho). O JSONL fica fora do banco.
- O CSV tem 7 colunas (`lexml_id, urn, titulo, autores, ano, descricao, outros_tipos`), mas `lexml_livros`
  não tem `autores`: o dataset não traz autor (a coluna vem vazia) e os autores chegam pelo enriquecimento
  da /urn, em `obras`. O `COPY` da Fase 1 precisa levar essa coluna vazia em conta.
- RLS: leitura pública; escrita só pelas Edge Functions (service role).
- Projeto grátis pausa após 7 dias sem uso: `supabase-keepalive.yml` faz ping 2x por semana.

### Checklist da Fase 1

- [ ] Criar projeto Supabase; migration com o esquema acima
- [ ] Importar o CSV (`COPY`) e conferir contagem (83.612)
- [ ] RPC `buscar_livro(texto, ano)`: top 10 por similaridade de título sem acento, ano como desempate
- [ ] RLS + secrets `SUPABASE_URL` e `SUPABASE_ANON_KEY` no GitHub (ativa o keepalive)
- [ ] `EXPLAIN ANALYZE` com e sem o índice trigram (exercício do teacher)

## App (Fase 2)

### Modelo de dados no aparelho (Core Data)

| Entidade | Campos | Regras |
| --- | --- | --- |
| `Estante` | id (UUID), nome, criadaEm | `livros` com exclusão em cascata; a interface confirma quantos livros serão apagados e oferece movê-los |
| `Livro` | id (UUID), titulo, subtitulo, autores, editora, edicao, ano, isbn13, paginas, cddir, urn, origem (lexml, googlebooks, gemini, manual), prateleira, fotoCapa, adicionadoEm | `estante` obrigatória (a chave fica no livro) |

- **Prateleira**: etiqueta de texto livre do usuário ("2ª de cima", "caixa azul"); sugerir as
  etiquetas já usadas naquela estante.
- **Exportar/importar**: `.json` versionado `{"versao": 1, "estantes": [...]}`, via folha de
  compartilhar e seletor de arquivos; UUIDs permitem **mesclar** ou **substituir** (perguntar).
  É também o backup contra a expiração do Sideloadly.

### Interface

- Botão da câmera embaixo, centralizado.
- Estantes em grade; estado vazio com livros esmaecidos `#cbe8f5` e "+" azul-escuro (conferir contraste).
- Topo: último livro escaneado + campo de busca (`.searchable`): título/autor → "Estante X · prateleira".
- Exportar/importar num menu (⋯) no canto superior.

### Checklist da Fase 2

- [ ] Modelo `Estantes.xcdatamodeld` + `PersistenceController` (com versão em memória)
- [ ] Tela inicial, estante → livros → detalhe, adição/edição manual, prateleira com sugestões
- [ ] Busca; exclusão com confirmação
- [ ] Exportar/importar (mesclar/substituir) + testes XCTest (exportar → importar → comparar)
- [ ] Simulador iOS 16, Sideloadly no iPhone, CI verde

## Identificação de livros (Fases 3 e 4)

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

### Avaliação (decide algoritmo × IA com números)

Conjunto de ~30 livros reais (fotos de capa + ficha) com gabarito anotado à mão; medir acerto por
campo do parser e do Gemini.

### Checklists

- Fase 3: câmera + `PhotosPicker`; conjunto de avaliação; parser ISBD/regex/layout/NLTagger; script de
  medição; RPC + pontuação; tela de confirmação (candidatos, "nenhum desses", manual, estante sugerida
  pela CDDir, prateleira); cache local.
- Fase 4: Edge Functions `enriquecer-urn` (porta de `data/enriquecer_urn.py`, 5 s entre pedidos) e
  `identificar-livro` (Google Books, Gemini; chaves como secrets); limite de chamadas por dispositivo.

## Fases 5 e 6

- Fase 5: foto da lombada das estantes, filtros por área/autor/edição, exportação com fotos (.zip),
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
