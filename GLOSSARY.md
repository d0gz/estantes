<!--
Formato adaptado de skills/engineering/domain-modeling/GLOSSARY-FORMAT.md, do repositório "skills"
de Matt Pocock (https://github.com/mattpocock/skills).
Copyright (c) 2026 Matt Pocock — licença MIT.
-->

# Estantes

Linguagem do domínio do Estantes: catalogar e achar livros, jurídicos ou não, de uma biblioteca física. Use
estes termos em nomes, testes, textos da interface e conversas; os da lista "Evitar" não.

## Obra e volume

**Obra**:
O trabalho intelectual, que pode ocupar vários volumes e ter várias edições.
_Evitar_: "livro" para o conjunto, coleção

**Livro**:
Um volume físico na biblioteca do usuário, com a sua ficha.
_Evitar_: item, registro, exemplar, obra (para um volume só)

**Tipo do livro**:
Jurídico ou geral (`TipoDeLivro`: `juridico`, `geral`). Muda o prompt do Gemini, o passo do LexML e um filtro na busca; não
aparece na lista. Na tela, o tipo geral se chama "Não jurídico".
_Evitar_: categoria, gênero, `naoJuridico`

**Edição**:
A versão publicada de uma obra, incluindo a reimpressão quando houver ("3.ª ed., 2.ª reimpr.").
_Evitar_: versão, tiragem

**Volume**:
Cada livro de uma obra publicada em partes, identificado por um número; o *rótulo do volume* é o
texto impresso ("Tomo XLVIII", "Vol. 24").
_Evitar_: tomo (só como rótulo impresso), fascículo

**Parte**:
Divisão da obra impressa na folha de rosto ("Parte Geral", "Parte Especial").
_Evitar_: seção, capítulo

**Subtítulo**:
Texto que completa o título; nos volumes, a matéria tratada, impressa abaixo do rótulo do volume
("Direito das Obrigações: Contrato coletivo do trabalho. …").
_Evitar_: descrição, ementa

**Intervalo de artigos**:
Os artigos de lei comentados no volume ("Arts. 1.710-1.779").
_Evitar_: faixa, âncora

**Colaborador**:
Quem participa do livro sem ser autor, com o papel como vem impresso ("prefácio de Aurélio Wander
Bastos", tradução, organização, coordenação). Aparece na ficha do livro, não no cabeçalho.
_Evitar_: coautor, contribuidor

**Série**:
Coleção editorial a que o livro pertence, como impressa na ficha CIP.
_Evitar_: coleção

## Sumário

**Sumário**:
Lista ordenada das divisões do livro, com página, impressa no início. A dica da etapa de captura pode citar que ele se chama
"índice" ou "tábua das matérias" em alguns livros.
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
ISBN, CDD e assuntos. Exceção: nos textos da tela é "ficha catalográfica", porque o usuário não conhece a sigla.
_Evitar_: ficha técnica; ficha catalográfica (fora dos textos da tela)

**ISBN**:
Número internacional do livro. O app guarda sempre a forma de 13 dígitos, sem hífens (começa com 978 ou
979); o ISBN-10 dos livros anteriores a 2007 é convertido ao salvar.
_Evitar_: código de barras (é o EAN-13 que carrega o ISBN), ISBN-10 como valor guardado

**Folha de rosto**:
Página do início do livro com título, autor, edição, editora e local; a fonte principal para livros antigos.
_Evitar_: capa, página de título

**Foto do livro**:
A foto que identifica o livro na lista da estante; livre, escolhida pelo usuário (capa, folha de rosto ou outra).
Uma por livro. No código, o nome continua `fotoMiniatura`: renomear não traria ganho ao usuário.
_Evitar_: capa, foto da capa (a capa lisa não identifica o livro; a foto pode ser outra), foto da miniatura

**Etapa de captura**:
Cada passo de fotografar um livro novo: capa, ficha ou folha de rosto e sumário.
_Evitar_: passo, fase (fase é do projeto)

**Ficha ou folha de rosto**:
A etapa de uma foto só: a ficha CIP, se o livro tiver; senão, a folha de rosto. Nunca as duas. No código, `fichaOuRosto` e
`ficha_ou_rosto`.
_Evitar_: contracapa, "página de identificação" na interface

**Página capturada**:
A cópia reduzida de uma foto do fluxo, com o papel (capa, ficha ou folha de rosto, sumário) e o texto lido. É temporária, fica só
em memória e só a foto do livro é gravada.
_Evitar_: foto do livro (é a escolhida para ficar), imagem

**Conferência**:
A tela depois da captura e antes do envio: fotos por etapa, estrela da foto do livro e o botão "Identificar livro".
_Evitar_: conferência para a regra (é a validação da extração) ou para a tela depois do Gemini (é a revisão)

**Revisão**:
A tela depois do Gemini, com a ficha e o sumário preenchidos; o usuário corrige e salva.
_Evitar_: confirmação, conferência

**Validação da extração**:
A regra pura que confere a resposta do Gemini com o ISBN e o sumário antes da revisão, sem corrigir nada sozinha.
_Evitar_: conferência, correção

**Local de publicação**:
A cidade onde o livro foi publicado.
_Evitar_: "local" sozinho (confunde com prateleira)

**Catálogo**:
A base do LexML no servidor. Serve só à parte opcional da identificação, em livros jurídicos: confirmar o livro e trazer a CDDir.
_Evitar_: base, banco, acervo

**Identificação**:
Extrair das fotos a ficha e o sumário do livro, com o Gemini, para o usuário revisar.
_Evitar_: reconhecimento, cadastro

**Busca**:
Procurar por texto, só na biblioteca do usuário, livros e itens do sumário.
_Evitar_: pesquisa, consulta ao catálogo

**Origem**:
De onde veio um dado: LexML, Google Books, Gemini, manual e, no sumário, foto.
_Evitar_: fonte
