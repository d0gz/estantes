-- Esta funcao busca um livro no banco de dados a partir de um texto e um ano opcional. Ela retorna os livros que possuem títulos semelhantes ao texto fornecido, ordenados pela similaridade e pela proximidade do ano, limitando o resultado a 10 registros.
-- o search path = '' é necessário pois o search path padrão inclui o schema 'extensions' e 'public' que pode ser um problema pois se nao definir como vazio, vamos buscar o primeiro objeto na ordem que representa as funcoes f_unaccent e similarity, podendo eles estar em um schema malicioso e serem funcoes falsas. Usando o path vazio limita o que o banco de dados pode acessar, assim definimos o caminho para o schema desejado para tabelas (from), funcoes operadores. O search path fixado em vazio limita o dano que a funcao pode causar quando ela pode alcançar um schema que você não quer que o usuário chamador alcance. O security invoker é necessário para que a função seja executada com os privilégios do chamador, pois no caso ruim, se temos um security definer, o chamador poderia acessar dados que ele não deveria acessar, o risco é quando o search_path não está fixado, dai teriamos uma funcao "falsa" que chama objetos maliciosos incorretos e esta sendo executada com permissoes de dono que ignoram (BYPASS) o Row Level Security (RLS) que definimos para os papéis anon e authenticated.

begin;
create or replace function public.buscar_livro(p_texto text, p_ano smallint default null)
returns table (lexml_id text, urn text, titulo text, ano smallint, descricao text, media_similaridade real)
language sql stable parallel safe
security invoker set search_path = ''
as $$
  select 
    l.lexml_id,
    l.urn,
    l.titulo,
    l.ano,
    l.descricao,
    (extensions.word_similarity(lower(public.f_unaccent(l.titulo)), lower(public.f_unaccent(p_texto))) + extensions.similarity(lower(public.f_unaccent(l.titulo)), lower(public.f_unaccent(p_texto)))) / 2 as media_similaridade
    from public.lexml_livros l
    where length(trim(p_texto)) >= 3
      and lower(public.f_unaccent(l.titulo)) operator(extensions.%) lower(public.f_unaccent(p_texto))
      order by media_similaridade desc,
      abs(l.ano - p_ano) nulls last,
      l.lexml_id
    limit 10;
$$;
revoke execute on function public.buscar_livro(text, smallint) from public;
grant execute on function public.buscar_livro(text, smallint) to anon, authenticated;

comment on function public.buscar_livro(text, smallint) is 'Busca livros por título e ano, retornando os 10 mais similares, where usa similarity pra filtrar (indice GIN), no order by faz a media entre similarity e word_similarity pra ter algo mais completo, desempata com ano e id..';
commit;

