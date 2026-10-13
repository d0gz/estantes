<!--
Formato adaptado de skills/engineering/domain-modeling/GLOSSARY-FORMAT.md, do repositório "skills"
de Matt Pocock (https://github.com/mattpocock/skills).
Copyright (c) 2026 Matt Pocock — licença MIT.
-->

# Estantes

Linguagem do domínio do Estantes: catalogar e achar livros jurídicos de uma biblioteca física. Use
estes termos em nomes, testes, textos da interface e conversas; os da lista "Evitar" não.

## Obra e volume

**Obra**:
O trabalho intelectual, que pode ocupar vários volumes e ter várias edições.
_Evitar_: "livro" para o conjunto, coleção

**Livro**:
Um volume físico na biblioteca do usuário, com a sua ficha.
_Evitar_: item, registro, exemplar, obra (para um volume só)

**Edição**:
A versão publicada de uma obra, incluindo a reimpressão quando houver ("3.ª ed., 2.ª reimpr.").
_Evitar_: versão, tiragem

**Volume**:
Cada livro de uma obra publicada em partes, identificado por um número; o *rótulo do volume* é o
texto impresso ("Tomo XLVIII", "Vol. 24").
_Evitar_: tomo (só como rótulo impresso), fascículo

**Parte**:
Texto da folha de rosto que delimita a matéria tratada no volume.
_Evitar_: seção, capítulo

**Intervalo de artigos**:
Os artigos de lei comentados no volume ("Arts. 1.710-1.779").
_Evitar_: faixa, âncora

**Série**:
Coleção editorial a que o livro pertence, como impressa na ficha CIP.
_Evitar_: coleção

## Sumário

**Sumário**:
Lista ordenada das divisões do livro, com página, impressa no início.
_Evitar_: índice, tabela de conteúdo

**Item do sumário**:
Uma entrada do sumário: numeração, título, página e nível.
_Evitar_: linha, tópico

**Numeração**:
O prefixo impresso de um item do sumário ("Capítulo II", "1.2.3", "Art. 1.710", "§ 5.108").
_Evitar_: rótulo, prefixo, âncora

**Nível**:
A profundidade do item na hierarquia do sumário; 1 é o topo.
_Evitar_: recuo, indentação

**Índice remissivo**:
Lista alfabética de assuntos no fim do livro, com páginas; não é o sumário.
_Evitar_: índice (sozinho)

## Organização

**Biblioteca**:
Todas as estantes do usuário juntas; é o que a busca percorre.
_Evitar_: acervo, catálogo

**Estante**:
Conjunto nomeado de livros do usuário; cada livro está em exatamente uma.
_Evitar_: coleção, pasta, lista

**Prateleira**:
Etiqueta livre que diz onde o livro fica fisicamente dentro da estante ("2ª de cima", "caixa azul").
_Evitar_: seção, local, posição

**Categoria**:
Etiqueta de assunto escolhida pelo usuário, com uma cor; um livro pode ter várias.
_Evitar_: assunto, tag, tema

## Catalogação e identificação

**CDDir**:
Classificação Decimal de Direito: código hierárquico de assunto jurídico, com os nomes dos seus níveis.
_Evitar_: CDD (a classificação decimal geral, que vem na ficha CIP, é outra)

**Ficha CIP**:
Ficha de Catalogação na Publicação, impressa no verso da folha de rosto, com autor, título, edição,
ISBN, CDD e assuntos.
_Evitar_: ficha técnica, ficha catalográfica

**Folha de rosto**:
Página do início do livro com título, autor, edição, editora e local; a fonte principal para livros antigos.
_Evitar_: capa, página de título

**Foto da miniatura**:
A foto que identifica o livro na lista da estante; livre, escolhida pelo usuário (capa, folha de rosto ou outra).
Uma por livro.
_Evitar_: capa, foto da capa (a capa lisa não identifica o livro; a foto pode ser outra)

**Local de publicação**:
A cidade onde o livro foi publicado.
_Evitar_: "local" sozinho (confunde com prateleira)

**Catálogo**:
A base do LexML no servidor, usada só para identificar livros.
_Evitar_: base, banco

**Identificação**:
Achar no catálogo, ou nas fontes de reserva, a ficha do livro fotografado.
_Evitar_: reconhecimento, cadastro

**Busca**:
Procurar por texto, só na biblioteca do usuário, livros e itens do sumário.
_Evitar_: pesquisa, consulta ao catálogo

**Origem**:
De onde veio um dado: LexML, Google Books, Gemini, manual e, no sumário, foto.
_Evitar_: fonte
