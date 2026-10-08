#!/usr/bin/env bash
# Importa o CSV do LexML (gerado por extrair_livros_lexml.py) para a tabela lexml_livros.
#
# Uso: ./data/importar_lexml.sh [caminho/do/livros_lexml.csv]   (padrão: data/livros_lexml.csv)
#
# Lê SUPABASE_DB_URL do .env. Roda numa transação só: ou entram todos os livros, ou nenhum.
# Recusa importar se a tabela já tiver linhas (rodar de novo daria chave duplicada no meio).
#
# Por que \copy e não COPY: o COPY lê o arquivo no disco do SERVIDOR e exige o papel
# pg_read_server_files, que o usuário postgres do Supabase não tem. O \copy do psql lê o
# arquivo aqui no Mac e o envia pela conexão (COPY ... FROM STDIN), o que qualquer papel pode.
set -euo pipefail

raiz="$(cd "$(dirname "$0")/.." && pwd)"
csv="${1:-$raiz/data/livros_lexml.csv}"

if [ ! -f "$csv" ]; then
  echo "CSV não encontrado: $csv" >&2
  exit 1
fi
set -a; source "$raiz/.env"; set +a

# O CSV entra pela entrada padrão (pstdin); o SQL vem do here-doc, pelo -f.
psql "$SUPABASE_DB_URL" -X -q -v ON_ERROR_STOP=1 -f <(cat <<'SQL'
begin;

do $$
begin
  if exists (select 1 from lexml_livros) then
    raise exception 'lexml_livros já tem linhas; esvazie a tabela antes de importar de novo';
  end if;
end $$;

-- Staging: as 7 colunas do CSV, todas como texto. Some sozinha no fim da transação.
create temp table lexml_staging (
  lexml_id     text,
  urn          text,
  titulo       text,
  autores      text,             -- sempre vazia no dataset; descartada abaixo
  ano          text,
  descricao    text,
  outros_tipos text
) on commit drop;

-- CSV com cabeçalho; o BOM (EF BB BF) fica na linha de cabeçalho, que é pulada.
\copy lexml_staging from pstdin with (format csv, header true, encoding 'UTF8')

-- Só as 6 colunas da tabela. nullif: texto vazio vira NULL (ausência de dado, não string vazia).
insert into lexml_livros (lexml_id, urn, titulo, ano, descricao, outros_tipos)
select lexml_id,
       urn,
       nullif(titulo, ''),
       nullif(ano, '')::smallint,
       nullif(descricao, ''),
       nullif(outros_tipos, '')
from lexml_staging;

commit;

-- Atualiza as estatísticas que o planner usa para escolher entre o índice e a varredura.
analyze lexml_livros;

\echo 'Conferência (esperado: 83612 | 2 | 1556 | 2017 | 19936 | 4182 | 1235):'
select count(*)                                   as livros,
       count(*) filter (where titulo is null)     as sem_titulo,
       min(ano)                                   as ano_min,
       max(ano)                                   as ano_max,
       count(*) filter (where descricao like 'Sumário%') as com_sumario,
       count(*) filter (where descricao like 'Resumo%')  as com_resumo,
       count(outros_tipos)                        as com_outros_tipos
from lexml_livros;
SQL
) < "$csv"
