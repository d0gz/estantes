-- Esquema inicial do catálogo (Fase 1): extensões, f_unaccent, tabelas, índices e RLS só de leitura.
-- Aplicar com: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f <este arquivo>
begin;

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
  edicao   text,
  ano      smallint,
  editora  text,
  local    text,
  paginas  text,
  isbn13   text[] not null default '{}'
);
create index edicoes_isbn13 on edicoes using gin (isbn13);
create index edicoes_obra on edicoes (obra_id);

alter table lexml_livros enable row level security;
create policy "leitura_publica"
on lexml_livros
for select
to anon, authenticated
using (true);

alter table obras enable row level security;
create policy "leitura_publica"
on obras
for select
to anon, authenticated
using (true);

alter table edicoes enable row level security;
create policy "leitura_publica"
on edicoes
for select
to anon, authenticated
using (true);

-- Grants explícitos: o padrão do Supabase dá TRUNCATE ao anon e não dá SELECT.
revoke all on lexml_livros, obras, edicoes from anon, authenticated;
grant select on lexml_livros, obras, edicoes to anon, authenticated;

commit;
