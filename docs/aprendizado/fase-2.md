# Fase 2 — App

Objetivo da fase: construir o app iOS (SwiftUI + Core Data) em camadas: entidades e regras puras no Domínio, persistência em Dados, telas em Apresentação, e a busca local (índice invertido + BM25F) sobre a biblioteca do usuário.

## Tarefa 2.1 — Entidades do Domínio e a porta BibliotecaRepositorio (2026-10-08)

### O que foi feito
Criamos as entidades puras em `ios/Estantes/Dominio/Entidades/` (`Estante`, `Livro`, `ItemSumario`, `Categoria`, mais os enums `OrigemLivro`, `OrigemItemSumario` e `CorCategoria`), a regra `NomeDeCategoria` e a função `Normalizacao.chave` em `Dominio/Regras/`, e a porta `BibliotecaRepositorio` em `Dominio/Portas/`. Há 13 testes XCTest verdes no Xcode 14.2. A `ValidacaoSumario` ficou de fora de propósito: é a próxima tarefa e quem escreve é você.

### Conceitos envolvidos

**1. Struct versus classe versus NSManagedObject (semântica de valor).**
Em Swift, `struct` é tipo de valor: atribuir ou passar para uma função cria uma cópia independente. `class` é tipo de referência: duas variáveis apontam para o mesmo objeto. O teste `testStructsSaoValores` mostra isso:

```swift
var original = Livro(estanteId: UUID(), titulo: "Original")
let copia = original          // cópia
original.titulo = "Alterado"
// copia.titulo continua "Original"
```

Consequência prática: se a tela de detalhes recebe um `Livro` e o ViewModel da tela de edição altera o dele, uma tela não muda o livro da outra por acidente. Com uma classe, as duas veriam a mesma mudança (estado compartilhado, a fonte clássica de bugs de UI).

`NSManagedObject` é pior ainda para as telas: é uma referência presa a um `NSManagedObjectContext` e à thread (ou fila) desse contexto. Tocar nele de outra thread é comportamento indefinido, e ele "se atualiza sozinho" quando o contexto muda. Já uma struct com `import Foundation` apenas permite testes que rodam em milissegundos, sem Core Data, sem simulador de banco, sem nada.

**2. Identidade: UUID gerado no aparelho.**
Cada entidade tem `id: UUID`. Um UUID v4 tem 122 bits aleatórios; a chance de colisão é desprezível sem precisar de coordenação central. Isso permite MESCLAR na importação: "mesmo UUID = mesmo livro". Por que não as alternativas: o `NSManagedObjectID` é temporário até o primeiro save (vira permanente depois) e é específico daquele armazenamento, então não sobrevive a uma exportação; um número sequencial (1, 2, 3...) colide entre duas bibliotecas diferentes, que começam ambas do 1.

**3. Relações: a chave estrangeira fica no lado "muitos".**
`Livro.estanteId` aponta para a estante; a `Estante` não guarda a lista de livros. É o mesmo desenho do SQL da Fase 1 (`livro.estante_id REFERENCES estante`). Guardar nos dois lados criaria duas fontes da mesma verdade, que precisariam ser mantidas em sincronia.

**4. Agregado (Domain-Driven Design).**
Um agregado é um grupo de objetos tratados como uma unidade de consistência, com uma raiz pela qual tudo passa. Aqui, `Livro` é a raiz e contém `itensSumario`: o sumário vive, morre e é salvo junto com o livro, e na importação é substituído em bloco. `Categoria`, ao contrário, tem vida própria (existe sem livros, é compartilhada por vários), então o livro guarda só `categoriaIds: Set<UUID>`. Renomear uma categoria muda um registro só, sem regravar nenhum livro. Um `Set` (e não `[UUID]`) porque a ordem não importa e não há repetição.

Decorrência importante: **a posição no array É a ordem do sumário**. Não existe campo `ordem` na struct. O repositório (2.2) gravará o índice no atributo `ordem` do Core Data e ordenará ao ler. Se a struct também tivesse `ordem`, haveria duas verdades possíveis (array diz uma coisa, campo diz outra).

**5. Opcionais.**
`String?` é açúcar para `Optional<String>`, um enum com dois casos: `.none` (escrito `nil`) e `.some(valor)`. O compilador obriga a tratar a ausência antes de usar o valor, o que elimina uma classe inteira de erros de ponteiro nulo. Usamos opcional onde a ausência é um estado legítimo do mundo (livro manual sem ISBN, item "Parte I" sem página), e não opcional onde a ausência seria bug (`titulo`, `id`). Você vai usar muito:

```swift
if let p = item.pagina { ... }      // desembrulha com segurança
item.pagina ?? 0                     // valor padrão
item.numeracao?.isEmpty              // encadeamento: resultado também é opcional
```

**6. Enum com valor bruto (`enum X: String`) e `CaseIterable`.**
Em Swift, enums são tipos soma: um valor é exatamente um dos casos. `enum OrigemLivro: String` associa a cada caso uma `String` (por padrão, o próprio nome do caso): `OrigemLivro.lexml.rawValue == "lexml"`, e `OrigemLivro(rawValue: "gemini")` devolve um opcional (pode não existir). `CaseIterable` gera `allCases`, um array com todos os casos, na ordem de declaração. Os testes usam isso para travar os valores: `OrigemLivro.allCases.map(\.rawValue)`. O `\.rawValue` é um key path usado como função.

Por que travar por teste: o valor bruto vai para o Core Data e para o arquivo exportado. Se alguém renomear `googlebooks` para `googleBooks`, os arquivos antigos deixam de decodificar. O teste transforma uma regra "de cabeça" em falha de build.

**7. Protocolo + inversão de dependência (a porta).**
`BibliotecaRepositorio` é um `protocol`: um contrato de métodos, sem implementação. O Domínio declara do que precisa; a camada Dados implementa com Core Data. A seta de dependência no código aponta de Dados para Domínio (Dados importa o protocolo), o inverso do que seria o caminho "ingênuo" em que o Domínio chamaria o Core Data. Esse é o "D" do SOLID.

```mermaid
flowchart LR
    A[Apresentacao: ViewModels] --> D[Dominio: BibliotecaRepositorio]
    C[Dados: RepositorioCoreData] -->|implementa| D
    T[Testes: RepositorioEmMemoria] -->|implementa| D
```

Ganhos: trocar Core Data por um falso em memória nos testes e previews, ou por SwiftData no futuro, sem mexer em nenhuma tela.

**8. `async throws`.**
`throws` porque gravar em disco pode falhar e o chamador deve ser forçado a tratar (`try`). `async` porque o Core Data faz o trabalho num contexto de segundo plano (`perform`); um ViewModel `@MainActor` chama com `await`, suspendendo a função sem bloquear a thread principal (a tela continua respondendo). `async` não significa "outra thread" por si só: significa "pode suspender neste ponto".

**9. Normalização de texto.**
`Normalizacao.chave` faz `folding` com `.caseInsensitive` e `.diacriticInsensitive` (usando a localidade `pt_BR`), depois quebra em palavras por espaço em branco e junta com um espaço só. Resultado: `"  Direito   Tributário "` vira `"direito tributario"`. É a base tanto da unicidade de categorias quanto, na 2.3, da busca. Custo: O(n) no tamanho do texto, uma passada.

**10. Regra pura: `NomeDeCategoria.validar`.**
Função estática, sem estado e sem efeito colateral: mesma entrada, mesma saída. Devolve `Problema?` (`nil` = válido), com `.repetido(Categoria)` carregando a categoria conflitante para a interface poder dizer "já existe 'Direito Tributário'". O parâmetro `ignorando:` permite renomear mantendo o próprio nome. Note o idioma `repetida.map { .repetido($0) }`: `Optional.map` aplica a função só se houver valor, e propaga `nil` caso contrário.

**11. XCTest (para a próxima tarefa).**
Cada classe de teste herda de `XCTestCase`; cada método que começa com `test` roda isolado, com uma instância nova da classe. As asserções principais: `XCTAssertEqual(a, b)`, `XCTAssertNil`, `XCTAssertTrue`. `@testable import Estantes` dá acesso aos símbolos `internal` do app. O padrão é Arrange (montar entrada), Act (chamar), Assert (conferir). Para a `ValidacaoSumario`, o jeito natural é um teste por regra: nível zero, nível que pula de 1 para 3, título vazio, página que regride (aviso, não erro).

**12. `for ... enumerated()` (para a próxima tarefa).**
`for (indice, item) in itens.enumerated()` percorre a sequência produzindo pares (posição a partir de 0, elemento). Você precisará dele na `ValidacaoSumario` para dizer "o item da posição 3 está errado" e para comparar cada item com o anterior (`itens[indice - 1]`, cuidando do caso `indice == 0`, senão o programa trava com índice fora do limite).

### Por que assim
- **Struct em vez de classe/NSManagedObject**: segurança contra estado compartilhado, testes rápidos, Domínio sem dependências (regra do projeto).
- **UUID**: permite mesclar na importação sem coordenação central.
- **Livro como raiz de agregado, sem campo `ordem`**: uma verdade só sobre a ordem do sumário; salvar e importar em bloco.
- **`categoriaIds` em vez de `[Categoria]` dentro do livro**: renomear categoria não regrava livros.
- **Foto da capa fora da struct** (`fotoCapa(doLivro:)`, `salvarFotoCapa`): o índice da busca carrega todos os livros ao abrir; imagens pesariam na memória. No Core Data, será "Allows External Storage" (o Core Data guarda blobs grandes como arquivos fora do SQLite).
- **`numeracao` separada do `titulo`**: toda origem grava no mesmo formato, e o título limpo ajuda a busca. Preserva "Capítulo" versus "Título".
- **`pagina` opcional e `origem` por item**: "Parte I" não tem página; um sumário pode ser misto (LexML com correções manuais).
- **`ValidacaoSumario` única para todas as origens** (função pura devolvendo erros e avisos): o formulário (2.6) e o parser (Fase 3) usam a mesma regra, garantindo formato único. Página que regride é aviso, não erro, por causa de apêndices.
- **Nome de categoria validado no Domínio**: a restrição de unicidade do Core Data diferencia acentos e não dá mensagem útil.
- **`CorCategoria` como enum**: `Color` é SwiftUI (proibido no Domínio); um hex é um tom só, e cada cor precisa de versão clara e escura; paleta fixa permite conferir contraste uma vez; valor bruto estável.
- **Dois enums de origem**: um enum único permitiria combinações sem sentido (item vindo do Google Books). Tornar estados inválidos irrepresentáveis é melhor do que validá-los.
- **Um repositório só**: "substituir" na importação troca tudo numa transação.
- **Sem `Codable` nas entidades**: a exportação (2.8) terá um DTO próprio (`BibliotecaExportadaV1`) em Dados, para que o formato do arquivo não mude quando a struct mudar.
- **Inits com valores padrão**: `Livro(estanteId:titulo:)` basta em testes e previews.
- **Sem iPhone, `PhotosPicker` como alternativa a toda captura**: a câmera e o `VNDocumentCameraViewController` não funcionam no simulador (`isSupported` falso), mas Vision e `PhotosPicker` funcionam. Fotos entram no simulador arrastando ou com `xcrun simctl addmedia booted foto.jpg`.

### Alternativas descartadas
- `NSManagedObject` nas telas: acopla UI à persistência e à thread do contexto.
- Classes no Domínio: estado compartilhado.
- `NSManagedObjectID` ou inteiro sequencial como identidade: ver conceito 2.
- Numeração dentro do título ou descartá-la: ver "Por que assim".
- Enum único de origem: combinações sem sentido.
- Cor por hex ou por `Color`: ver acima.
- Restrição de unicidade do Core Data para categorias.
- `Repositorio<T>` genérico: parece elegante, mas esconde regras próprias de cada entidade (apagar estante com destino, substituir sumário em bloco, nullify em categoria).
- Um repositório por entidade: quebraria a transação única da importação.
- Campo `ordem` na struct: duas fontes da mesma verdade.

### Padrões e boas práticas
- **Repository + inversão de dependência**: use quando há mais de uma implementação plausível (produção, teste, preview). NÃO use quando só existe uma e nunca vai mudar; aí é cerimônia.
- **Injeção por `init`**, sem singletons (regra do projeto).
- **Tornar estados inválidos irrepresentáveis** (enums por origem, `Set` para categorias).
- **Funções puras para regras** (`NomeDeCategoria`, `ValidacaoSumario`): testáveis sem preparação.
- **Test de contrato para valores persistidos** (os valores brutos travados).
- **Quando NÃO usar struct**: quando a identidade do objeto importa mais que o valor (um serviço com conexão aberta, um cache compartilhado) ou quando é preciso herança.

### Armadilhas
- Renomear um caso de enum com valor bruto implícito muda o `rawValue` silenciosamente. Para valores persistidos, declare-os explicitamente (`case lexml = "lexml"`) ou mantenha o teste de contrato.
- `let id` em struct impede alterar a identidade depois de criada (bom), mas lembre que `var` em struct só funciona se a instância também for `var`.
- Comparar nomes sem normalizar: `"Tributário" == "tributario"` é falso em Swift. Sempre passe por `Normalizacao.chave`.
- `Equatable` sintetizado compara todos os campos, inclusive `adicionadoEm`. Para dois livros "iguais" em dados mas criados em momentos diferentes, `==` dá falso.
- Acessar `itens[indice - 1]` com `indice == 0` trava o app (crash em tempo de execução, não erro de compilação).
- Se um teste falhar só na CI, lembre que lá o Xcode é 26 e aqui é 14.2; o `folding` e a localidade podem ter diferenças sutis entre versões do sistema.

### Para ir além
- The Swift Programming Language (docs.swift.org): capítulos "Structures and Classes", "Enumerations" e "Optional Chaining".
- Eric Evans, *Domain-Driven Design* (agregados e repositórios) ou, mais curto, o texto de Martin Fowler "Repository" e "DDD_Aggregate" em martinfowler.com.
- Documentação da Apple: "XCTest" e "Concurrency" (async/await) no Swift book.

### Perguntas
1. Com suas palavras: por que `Livro` guarda `categoriaIds: Set<UUID>` e `itensSumario: [ItemSumario]` de maneiras tão diferentes (ids de um lado, os itens inteiros do outro)? O que isso muda ao renomear uma categoria e ao apagar um livro?
2. O que mudaria no desenho se o app precisasse sincronizar a biblioteca entre dois iPhones? Pense em identidade (UUID), no campo `ordem` e no que o DTO de exportação passaria a precisar guardar.
3. Preveja: `NomeDeCategoria.validar("Ação", existentes: [Categoria(nome: "acao", cor: .azul)])` devolve o quê? E `Normalizacao.chave("Ação")` comparado a `"ação"` (com o `ç` e o `ã` já decompostos em letra + acento)? Por que importa que o `folding` trate os dois igual?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

## Tarefa 2.1b — ValidacaoSumario, o primeiro código Swift do Ricardo (2026-10-08)

### O que foi feito
Ricardo escreveu sozinho `ValidacaoSumario.validar` em `ios/Estantes/Dominio/.../ValidacaoSumario.swift` (tarefa `[eu escrevo]`). O Claude preparou o esqueleto (tipos `Problema` e `Resultado`) e 11 testes de especificação, escritos antes do código (TDD: vermelho, depois verde), e atuou como revisor. No fim há 25 testes verdes no Xcode 14.2 e o PR #19 está aberto. Um teste foi acrescentado pelo próprio Ricardo (`testComparaComAPaginaImediatamenteAnterior`) depois de descobrirmos um buraco na especificação.

### A regra
Percorrer os itens; para cada índice `i`:
1. Nível menor que 1 gera erro `nivelInvalido`. Senão, se o nível subiu mais de 1 em relação ao anterior (o anterior vale 0 para o primeiro item), gera erro `saltoDeNivel`. Descer qualquer quantidade é permitido.
2. Título vazio ou só com espaços gera erro `tituloVazio`.
3. Página menor que a do último item anterior COM página (itens `nil` são pulados) gera AVISO `paginaMenorQueAnterior`.

A ordem é por índice, e o nível vem antes do título. Avisos não impedem salvar: `valido` é `erros.isEmpty`.

### O percurso (a parte mais didática)

**Rodada 1: três problemas de uma vez.**

1. `return Resultado(erros: [], avisos: [])` devolvia literais vazios em vez das variáveis preenchidas no `for`. Resultado: TODOS os testes de erro falharam com mensagens do tipo `("[]") is not equal to ...`. Ricardo achou que o defeito estava só na página, mas a pista estava na mensagem: até os testes de nível e de título mostravam `[]`. **Lição: ler a mensagem do teste antes de diagnosticar.**

2. A memória da página estava errada: `var pagItemAnterior = itens.first(where: { $0.pagina != nil })` fixava a memória no PRIMEIRO item com página, e ela nunca era atualizada.

3. A tentativa de atualizar era `if var pagAtual = ..., var pagAnterior = pagItemAnterior?.pagina, ... { pagAnterior = pagAtual }`. O `if var` cria uma CÓPIA local, que morre no `}`. É a semântica de valor (a mesma ideia do `testStructsSaoValores` da 2.1): mexer na cópia não mexe no original. Além disso, a atualização só aconteceria quando houvesse aviso.

Rastreamento com páginas 10, 50, 20 (o que o código dele fazia versus o correto):

| Volta | Página | Código dele compara com | Resultado | Deveria comparar com |
| --- | --- | --- | --- | --- |
| 0 | 10 | 10 | 10<10? não | nada |
| 1 | 50 | 10 | 50<10? não | 10 |
| 2 | 20 | 10 | 20<10? não, sem aviso (errado) | 50, aviso (certo) |

**Achado importante: falha da especificação, não do aluno.** Corrigido o `return`, os 11 testes originais PASSARIAM mesmo com a lógica de página errada, porque nenhum deles tinha uma sequência em que o item anterior com página difere do primeiro item com página. **Teste verde não prova que o código está certo. Prova só que ele faz o que os testes perguntam.** Ricardo escreveu `testComparaComAPaginaImediatamenteAnterior` (10, 50, 20, com aviso esperado no índice 2), viu o teste falhar e depois passar. Estrutura de um teste: monta (cenário), chama (a função), confere (o resultado).

Pseudocódigo para a memória: `ultimaPagina: Int? = nil` declarada FORA do `for`. Se o item tem página, compara quando há memória e depois atualiza SEMPRE (com ou sem aviso). Item sem página não mexe na memória.

**Rodada 2: o compilador entra em cena.**
- `if pagItemAnterior != nil && element.pagina < pagItemAnterior` sem chaves. Swift exige `{}` em todo `if`, o que evita o erro clássico de a segunda linha "parecer" dentro do `if`.
- Comparar `Int?` com `<` não compila. Checar `!= nil` não muda o tipo: Swift não faz "smart cast" como Kotlin ou TypeScript. A solução é `if let`, que desembrulha e cria uma constante `Int`; a vírgula encadeia desembrulho e condição. Exemplo usado: `if let precoHoje = ..., let precoOntem = ..., precoHoje > precoOntem`.
- Novo erro: `return Resultado(erros: erros, avisos: erros)`. O compilador NÃO pega (os dois são `[Problema]`); os testes pegam. É o tipo de bug que tipos iguais escondem.

**Rodada 3 (correta):**
```swift
if let pagAtual = element.pagina {
    if let pagAnterior = pagItemAnterior, pagAtual < pagAnterior {
        avisos.append(.paginaMenorQueAnterior(indice: index))
    }
    pagItemAnterior = pagAtual   // atualiza SEMPRE que o item tem página
}
```
Ajuste aplicado na revisão: atribuir `pagAtual` (o `Int` já desembrulhado), não `element.pagina` (que é `Int?` e não encaixaria).

Ajustes de estilo aplicados: `.nivelInvalido(...)` com inferência de tipo em vez de `ValidacaoSumario.Problema.nivelInvalido`, e `trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` em vez de `isEmpty || trimmed == ""`. Parênteses desnecessários no `if` foram removidos.

**Pendências leves, por escolha dele:** `for (indice, item)` em português em vez de `(index, element)`, e `{` na mesma linha do `if`/`for` (convenção Swift; ele usa a linha seguinte). Não afetam o comportamento, só a leitura por outros desenvolvedores. Vale reconsiderar quando o projeto crescer ou ganhar um linter (SwiftLint).

### Conceitos envolvidos

**Optional (`Int?`).** É um enum com dois casos, `.none` e `.some(valor)`. `Int?` e `Int` são tipos diferentes; por isso `<` não compila entre eles. `if let x = opcional` testa o caso e extrai o valor para uma constante de tipo `Int`, válida só dentro das chaves. Aqui: `element.pagina` é `Int?` porque "Parte I" não tem página.

**Semântica de valor.** `if var a = b` copia `b`. Alterar `a` não altera `b`. Para a memória sobreviver entre voltas do `for`, ela precisa ser declarada fora do laço e atribuída diretamente (`pagItemAnterior = pagAtual`).

**Escopo.** Variável declarada dentro do `for` nasce e morre a cada volta. A "memória entre iterações" tem de morar fora.

**Função pura.** `validar` recebe um array e devolve um `Resultado`, sem efeitos colaterais. Por isso o teste é só montar, chamar e conferir, sem banco, sem rede, sem tela.

**`enumerated()`.** Produz pares (posição, elemento). Evita `itens[i - 1]`, que travaria com `i == 0`. Aqui o "anterior" é guardado em variáveis (`itemAnteriorNivel`, `pagItemAnterior`), sem indexar o array.

**TDD e a limitação dos testes.** Vermelho, verde, refatorar. O teste é uma especificação executável, e uma especificação incompleta deixa passar código errado. O caso de teste novo nasce de um contraexemplo (10, 50, 20).

**Complexidade.** Uma passada pelo array: O(n) no tempo, O(1) de memória extra além da saída.

### Por que assim
- **Duas variáveis de memória** (`itemAnteriorNivel`, `pagItemAnterior`) em vez de olhar `itens[i-1]`: o nível compara com o item imediatamente anterior, mas a página compara com o último item que TEM página, e esses dois "anteriores" são diferentes.
- **Atualizar a memória sempre que há página**, mesmo sem aviso: o próximo item deve ser comparado com o mais recente, não com um valor antigo.
- **Nível: `if` / `else if`** porque nível inválido e salto são mutuamente exclusivos para um mesmo item (um nível 0 não é "salto"). Título é um `if` separado porque o mesmo item pode ter os dois problemas.
- **Página como aviso**, não erro: apêndices e anexos reiniciam a numeração.

### Alternativas descartadas
- **Guardar o índice do último item com página** e consultar `itens[ultimo]`: funciona, mas é mais indireto que guardar o próprio valor.
- **`reduce`**: possível, porém menos legível para quem está começando e sem ganho aqui.
- **`zip(itens, itens.dropFirst())`**: bom para comparar vizinhos, mas não cobre o "pula nil".
- **Lançar exceção no primeiro erro**: o usuário veria um problema por vez; devolver a lista completa permite mostrar tudo no formulário (2.6) e no parser (Fase 3).

### Padrões e boas práticas
- **Escrever o teste que falha antes de corrigir** (como no teste 10, 50, 20). NÃO vale a pena em código descartável.
- **Lista de problemas em vez de falhar no primeiro** (acumulador).
- **Enum com valores associados** (`.nivelInvalido(indice:)`): cada problema carrega o contexto.
- **Quando suspeitar de testes verdes:** ao corrigir um bug, pergunte "qual teste teria pegado isso?". Se nenhum, escreva-o primeiro.

### Armadilhas
- Literais no `return` (`[]`) em vez das variáveis: compila sem queixa.
- Campos do mesmo tipo trocados (`avisos: erros`): o compilador não vê. Só o teste vê.
- `if var` / `var` em ligação opcional: cria cópia, não altera o original.
- Nesta implementação, `itemAnteriorNivel = element.nivel` roda também quando o nível é inválido (por exemplo 0 ou negativo). Isso é coerente com o enunciado ("anterior" é o item anterior, seja ele válido ou não), mas vale um teste explícito se a regra mudar. Verifique nos testes se esse caso está coberto.

### Para ir além
- The Swift Programming Language (docs.swift.org): "The Basics" (Optionals e Optional Binding) e "Control Flow".
- Kent Beck, *Test-Driven Development: By Example*.
- Apple, documentação de XCTest (`XCTAssertEqual`) e "Structures and Classes" (semântica de valor).

### Perguntas
1. Com suas palavras: por que `if let pagAnterior = pagItemAnterior` resolve o erro de comparar `Int?` com `<`, e por que `!= nil` antes não resolveu? Por que `if var` NÃO atualizaria a memória?
2. Aplicação: se a regra mudasse para "página igual à anterior também é aviso", o que mudaria no código e qual teste você escreveria primeiro? E se itens sem página passassem a resetar a memória?
3. Raciocínio: com as páginas `[nil, 30, nil, 5, 40, 10]`, quais índices recebem aviso? Depois: se os testes originais passavam mesmo com a lógica errada, que outro tipo de entrada (além de 10, 50, 20) você acha que ainda não está coberta?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

(sem respostas)


---

## Tarefa 2.2 — Core Data e BibliotecaRepositorioCoreData (2026-10-08)

### O que foi feito
Criamos a camada de persistência em `ios/Estantes/Dados/Persistencia/`: o modelo `Estantes.xcdatamodeld` (Estante, Livro, ItemSumario, Categoria), as classes `EntidadesMO.swift`, o `PersistenceController` e o `BibliotecaRepositorioCoreData`, que implementa a porta definida na 2.1. A conversão entre objetos do banco e structs do Domínio ficou em `Conversao.swift` (parte escrita pelo Ricardo). Foram 25 testes de Dados escritos antes da conversão (TDD), depois ampliados na revisão; tudo verde no Xcode 14.2.

### Conceitos envolvidos

**Que banco é esse?** O Ricardo perguntou, e a resposta organiza a arquitetura:

| | Banco local (Core Data), 2.2 | Supabase (Postgres), Fase 1 |
|---|---|---|
| Onde | dentro do iPhone, arquivo SQLite `Library/Application Support/Estantes.sqlite` | servidor na internet |
| Guarda | a biblioteca do usuário (estantes, livros, sumários, categorias, capas) | o catálogo LexML (83.612 livros) |
| Quem escreve | o app | só nós via psql; o app só lê |
| Internet | não precisa (a busca também é offline) | precisa |
| Para quê | memória do app | identificar livro novo pela foto (Fase 3) |

Os dois se encontram na Fase 3: o resultado do Supabase é COPIADO para o banco local. A cadeia de leitura é:

```mermaid
flowchart LR
  Tela <--> S["struct Livro (Dominio)"] <--> C["Conversao.swift"] <--> MO[LivroMO] <--> CD[Core Data] <--> F[Estantes.sqlite]
```

Nos testes o arquivo é `/dev/null`. O app ainda não usa o banco: a montagem em `App/Dependencias` vem na 2.4. A exportação JSON (2.8) será o backup contra a expiração de 7 dias do Sideloadly.

**Core Data não é um banco, é um grafo de objetos.** Ele gerencia objetos em memória (`NSManagedObject`) e, por baixo, usa SQLite para persisti-los. Peças: o modelo (`NSManagedObjectModel`, o esquema), o `NSPersistentContainer` (empacota modelo + armazenamento + contextos) e o `NSManagedObjectContext` (a "mesa de trabalho": você altera objetos nela e só `save()` grava). Cada contexto tem uma fila (`perform`) em que seus objetos podem ser tocados; fora dela é comportamento indefinido.

**Regras de exclusão (delete rules).** Definem o que acontece com os objetos relacionados quando um é apagado:
- Estante→livros: *cascade* (apagar a estante apaga os livros);
- Livro→estante: obrigatória, *nullify*;
- Livro→itensSumario: *cascade*;
- Livro↔Categoria: muitos-para-muitos, *nullify* nos dois lados (apagar uma categoria só desfaz o vínculo, não apaga livros).
Toda relação tem inversa: o Core Data mantém os dois lados consistentes sozinho, e isso evita relações "pela metade".

**Classes `@NSManaged` e `@objc(LivroMO)`.** `@NSManaged` diz ao compilador "o acesso a esta propriedade será implementado em tempo de execução pelo Core Data" (ele gera getter/setter dinamicamente). `@objc(LivroMO)` fixa o nome Objective-C da classe: o modelo localiza a classe por nome, e sem isso o nome real seria `Estantes.LivroMO` (com o módulo na frente), e a busca falharia.

**Opcionais numéricos.** `@NSManaged var ano: Int32` não pode ser nil. Para campos opcionais usamos `NSNumber?`. Para `nivel` e `ordem` (obrigatórios), `Int32` escalar. Por isso a conversão tem `Int(nivel)` de um lado e `pagina?.intValue` do outro.

**Upsert.** "Busca pelo id; se não existir, cria; depois preenche." É o `salvar` do repositório. Sem restrição de unicidade no banco, a garantia é só da lógica do código (ver Armadilhas).

**`prateleiras`: SELECT DISTINCT.** Usamos `dictionaryResultType` com `returnsDistinctResults`: o SQLite devolve só a coluna pedida, sem materializar objetos, sem repetidos. `quantidadeDeLivros` usa `count(for:)`, que vira `SELECT COUNT(*)`: O(n) no banco, sem trazer n objetos para a memória.

**Sumário em bloco.** Em vez de uma relação ordenada (`NSOrderedSet`), o item tem um atributo `ordem` igual à posição no array. Salvar um livro apaga os itens antigos e recria. Simples e previsível; a relação ordenada é frágil e não funciona com CloudKit.

**Conversão em duas direções.**
- `paraDominio()`: LER. Banco → struct nova; devolve valor.
- `preencher(com:)`: GRAVAR. Copia struct → objeto que o repositório já criou ou buscou; não devolve nada.

### O percurso do Ricardo (o que cada tropeço ensina)

**1. "Dentro da extension, `id` é de quem?"** A primeira tentativa foi `Estante(id: UUID(), nome: "", criadaEm: Date())`: inventava valores novos em vez de ler o objeto. O que faltava: dentro de `extension EstanteMO { }`, `id`, `nome` e `criadaEm` são propriedades do PRÓPRIO objeto (`self.id`), uma linha do banco já carregada. A forma certa é `Estante(id: id, nome: nome, criadaEm: criadaEm)`: em `id: id`, o da esquerda é o rótulo do parâmetro do init da struct; o da direita é o valor lido de `self`. Efeito: as falhas caíram de 16 para 13.

**2. Categoria, sozinho e certo.** `Categoria(id: id, nome: nome, cor: CorCategoria(rawValue: cor) ?? .cinza)` e `cor = categoria.cor.rawValue`. O `?? .cinza` é uma degradação silenciosa. Alternativas: `fatalError` (fecha o app por causa de uma cor) ou `throw` (obrigaria `try` em toda leitura). O que protege contra renomear uma cor sem perceber é o teste de contrato dos `rawValue` da 2.1. Detalhe do revisor: salvar de novo grava o padrão por cima do valor desconhecido; isso é intencional e ficou comentado no arquivo.

**3. ItemSumario: de FALHAR para TRAVAR.** O `paraDominio()` saiu perfeito (`Int(nivel)`, `pagina?.intValue`, `?? .manual`). No `preencher`, ele escreveu `id = id`, `nivel = Int32(nivel)`, `numeracao = numeracao`, `titulo = titulo` (faltava o `item.`) e não gravou a `ordem`. Resultado: 5 testes com "Restarting after unexpected exit, crash". Por quê? O objeto recém-criado tem `id` nil no armazenamento, mas a classe declara `@NSManaged var id: UUID` sem `?`, prometendo ao Swift que nunca é vazio. Ler `id` para copiá-lo a si mesmo encontra nil onde se prometeu que não haveria, e o app encerra. Com o corpo vazio de antes ninguém lia o campo, e o Core Data só recusava salvar ("Multiple validation errors occurred."). Lição: um crash é pior que um teste vermelho, mas aponta para uma violação de contrato de tipo, e o sintoma mudou porque o código passou a LER o campo.

**4. Sombreamento (shadowing) e `self`.** O parâmetro `ordem` tem o mesmo nome da propriedade. Dentro da função, `ordem` é o parâmetro (constante), então `ordem = Int32(ordem)` não compila. A solução é `self.ordem = Int32(ordem)`, o único lugar do arquivo onde `self.` é obrigatório. Regra: o nome mais interno vence; `self.` desfaz o sombreamento. Na rodada 2 ele corrigiu tudo, com zero travamentos.

**5. LivroMO (escrito pelo Claude a pedido dele).** Pontos novos:
- `estanteId: estante.id`: a relação é o objeto inteiro, não o id;
- `Set(categorias.map(\.id))`: `map` devolve array, `Set` converte;
- `itensSumario.sorted { $0.ordem < $1.ordem }.map { $0.paraDominio() }`: relações do Core Data são conjuntos SEM ordem, e a ordem vem do atributo `ordem`;
- `"".components(separatedBy: "\n")` devolve `[""]` (um item vazio), não `[]`. Daí a função `lista(_:separador:)` com `texto.isEmpty ? [] : ...`. O teste `testLivroMinimoMantemOpcionaisNil` pegaria isso.
Estilo pedido por ele: um argumento por linha em init longo; `.map { ... }` sem parênteses (closure final).

### Por que assim
1. **Sufixo MO e classes à mão.** O codegen automático criaria `Livro` e `Estante`, colidindo com as structs do Domínio e visíveis no app inteiro. Com `MO`, a fronteira Dados/Domínio fica visível no nome.
2. **`autores` como String com um nome por linha (`\n`)**, porque nomes têm vírgula ("Sobrenome, Nome"). `cddirCaminho` usa " > ".
3. **`ItemSumario` com `id` no Core Data**: sem ele, a ida e volta (struct → banco → struct) não preserva a igualdade.
4. **Modelo carregado uma vez (`static let modelo`).** Vários containers, cada um com seu modelo, fazem o Core Data reclamar de entidades disputando a mesma classe. Não é singleton: é uma constante imutável, e o controller continua recebendo tudo por `init`.
5. **`/dev/null` nos testes.** Mesmo motor SQLite da produção, nada gravado. O tipo `NSInMemoryStoreType` é outro motor (sem batch requests e com diferenças sutis).
6. **Um `newBackgroundContext()` por operação** com `try await contexto.perform { }`: a tela não trava; cada operação começa sem cache antigo; nenhum MO sai do `perform`, só structs (que são valores seguros de passar entre filas).
7. **TDD com conferência prévia.** O Claude validou os próprios testes com uma conversão de referência temporária (não commitada) antes de passar a vez ao Ricardo. Assim, se um teste falhasse, a culpa só poderia ser da conversão dele. Teste que nunca viu o verde não prova nada.

### Alternativas descartadas
- **Codegen automático**: colisão de nomes (acima).
- **Transformable para `autores`**: opaco no banco, não buscável, exige transformer seguro; texto simples basta.
- **Relação ordenada (`NSOrderedSet`) para o sumário**: frágil, difícil de substituir em bloco, sem CloudKit.
- **SwiftData**: proibido pela regra dos dois Xcodes (exige iOS 17 e macros).
- **`NSInMemoryStoreType` nos testes**: motor diferente da produção.
- **Contexto único `viewContext` para tudo**: a escrita travaria a interface.

### Padrões e boas práticas
- **Repository + porta** (protocolo no Domínio, implementação em Dados): a tela não sabe que existe Core Data. Não vale a pena para um app de uma tela só, mas aqui o ganho é testar com um repositório falso e trocar a persistência.
- **Anti-corruption layer / mapper** (`Conversao.swift`): nenhum `NSManagedObject` vaza para fora de `Dados/Persistencia/`.
- **Regra de concorrência do Core Data**: cada objeto e cada contexto só dentro da sua fila (`perform`).
- **Idempotência**: apagar algo que não existe não é erro. Já gravar apontando para algo inexistente LANÇA erro, porque aí o chamador cometeu um engano real. A regra ficou documentada na porta: apagar ignora; ler devolve vazio; gravar com referência inexistente lança.
- **Verificar pelo compilador em vez de texto**: `#keyPath(LivroMO.estante.id)` no lugar de `"estante.id"`.
- **Desempate nas ordenações**: títulos iguais ("Direito penal") sem critério secundário voltam em ordem não determinística.

### Armadilhas
- **Bug real encontrado na revisão (no código do Claude)**: `apagarEstante(id: X, moverLivrosPara: X)` pulava o "mover" (`destino != id`) e a cascata apagava todos os livros, uma perda silenciosa de dados. Agora lança `destinoInvalido` antes de tocar no banco, com teste. Lição: caso de borda dentro de um `if` com duas condições; sempre pergunte "e se os dois valores forem iguais?".
- **Teste usando `viewContext` fora da fila principal**: passava por sorte. Passou a usar `newBackgroundContext()` + `perform`.
- **`/dev/null` nunca prova persistência**: por isso entrou um teste que fecha e reabre um banco em ARQUIVO de verdade.
- **Condição de corrida no upsert (limitação conhecida)**: dois `salvar` simultâneos do mesmo id, em contextos diferentes, ambos fazem "busca" sem achar e ambos criam, duplicando. Registrado no PLANO.md; resolver na 2.8 com um contexto único de escrita ou uniqueness constraints. É o clássico TOCTOU (time-of-check to time-of-use).
- **Valores de `@NSManaged` não opcionais lidos antes de preenchidos** travam o app (item 3 acima).
- **`components(separatedBy:)` com texto vazio** devolve `[""]`.
- **Sem versionamento do modelo**: antes de existirem dados reais de usuário, mudar o modelo exige migração. Adiado de propósito, mas deve ser feito antes de qualquer dado real.
- Diagnóstico geral: crash com "Restarting after unexpected exit" no teste significa quase sempre acesso inválido (nil em tipo não opcional, ou objeto fora da sua fila); veja o relatório de crash, não só o resumo.

Recusados ou adiados, com motivo: unicidade do nome da categoria (é regra do Domínio, decidida na 2.1); tamanho das fotos dentro da linha do Livro (decidir na 2.4); limpar espaços da prateleira (formulário na 2.4).

### Para ir além
- Apple, *Core Data* (developer.apple.com/documentation/coredata), em especial "Using Core Data in the Background" e "Core Data Model Editor".
- Martin Fowler, *Patterns of Enterprise Application Architecture*: Repository, Data Mapper.
- *The Swift Programming Language*, capítulo "Properties" e a seção sobre `self` e nomes de parâmetros.

### Perguntas
1. Com suas palavras: qual a diferença entre `paraDominio()` e `preencher(com:)`? Por que, em `id: id`, os dois `id` são coisas diferentes? Por que `ordem = Int32(ordem)` não compila e `self.ordem = Int32(ordem)` compila?
2. Aplicação: se o app passasse a ter uma tela de "categorias" em que apagar uma categoria também apagasse os livros dela, o que mudaria no modelo? E se quiséssemos guardar a ordem dos autores de um livro, o formato "um por linha" continuaria servindo?
3. Raciocínio: (a) por que `id = id` TRAVA o app, enquanto um `preencher` de corpo vazio apenas faz o teste falhar? (b) Descreva uma sequência de duas chamadas simultâneas de `salvar` que duplica um livro. (c) Por que apagar um id inexistente é ignorado, mas salvar um livro numa estante inexistente lança erro?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

---

**Lembrete:** as perguntas das entradas 2.1 e 2.1b continuam sem resposta. Vale respondê-las antes de seguir: as respostas a 2.1b (validação do sumário) e a 2.2 (conversão e concorrência) se apoiam em ideias que se acumulam.

---

## Tarefa 2.3a — Tokenizador da busca (2026-10-09)

### Correção das respostas (entradas anteriores)
(sem respostas) As perguntas das entradas 2.1, 2.1b e 2.2 continuam em branco. Nada a corrigir.

### O que foi feito
Primeiro passo da 2.3: `Dominio/Busca/Tokenizador.swift`, um `enum` sem casos com a função `termos(_:)`, que transforma um texto numa lista de termos prontos para o índice e para a consulta. Os testes estão em `EstantesTests/Dominio/Busca/TokenizadorTests.swift` (10 testes; a suíte inteira fechou em 60, 0 falhas, no Xcode 14.2). O comentário de `Normalizacao.swift` foi atualizado e o `PLANO.md` marcou o BM25F como `[eu escrevo]`. O Ricardo optou por não escrever o tokenizador e guardar o `[eu escrevo]` para a fórmula do BM25F, onde há mais a aprender.

### Conceitos envolvidos

**O mapa da 2.3.** O motor de busca local (offline, só Foundation) sai em cinco passos:

```mermaid
flowchart LR
  A["1. Tokenização<br/>e palavras vazias"] --> B["2. Índice invertido"]
  B --> C["3. BM25F<br/>[eu escrevo]"]
  C --> D["4. Filtros"]
  D --> E["5. Motor + resultado"]
```

Começamos pela tokenização por dois motivos. Primeiro, índice e consulta precisam passar pela MESMA normalização. Se divergirem, "Ação" indexado nunca casa com "acao" digitado, e o erro é silencioso: a busca simplesmente não acha nada. Segundo, é a peça menor e não depende de nenhuma outra.

**Tokenização.** É quebrar um texto em unidades (tokens ou termos) que o índice sabe comparar. É a primeira etapa de qualquer motor de busca (Lucene, Elasticsearch, Postgres full-text). O que difere entre eles é o pipeline, e o nosso tem três etapas:

```mermaid
flowchart TD
  T["'Lei 8.078/90 – Código de Defesa do Consumidor'"] --> N["1. Normalizacao.chave<br/>minúsculas, sem acento, espaços reduzidos"]
  N --> Q["2. Quebra<br/>letra ou dígito forma termo; o resto separa"]
  Q --> V["3. Remove palavras vazias"]
  V --> R["['lei','8078','90','codigo','defesa','consumidor']"]
```

1. **Normalização (folding pt_BR).** Reaproveita `Normalizacao.chave`. Por baixo, é a decomposição Unicode (NFD): "ç" vira "c" + cedilha combinante, e o folding descarta as marcas combinantes. Assim "AÇÃO" vira "acao".
2. **Quebra.** O código percorre um `Array(Character)` com `enumerated()` e acumula o termo atual numa `String`. Cada caractere é de um destes tipos: parte de termo (letra ou dígito, que entra no acumulador), ou separador (que fecha o termo, se houver). Pontuação, hífen e travessão são separadores, então "pós-graduação" vira `pos` + `graduacao`. É uma passada só, O(n) no tamanho do texto. Um `Character` do Swift é um grapheme cluster (o que o usuário vê como um caractere), por isso o `Array(Character)` é seguro com acentos, e não é um array de bytes ou de escalares Unicode.
3. **Palavras vazias (stop words).** Artigos, preposições e contrações (de, da, do, em, no, para, por, com, ou, que, se...) aparecem em quase todo título e quase não distinguem um livro do outro. Ficam guardadas num `Set<String>`, cuja consulta é O(1) em média (tabela hash), contra O(k) de varrer um array. Termos jurídicos curtos (lei, art, cpc, stf) ficam de propósito, porque aqui tamanho curto não significa pouca informação. A lista já vem sem acento, porque a normalização roda antes: "à" chega ao filtro como "a".

**Por que a lista mantém ORDEM e REPETIÇÕES.** `termos` devolve `[String]`, e não `Set<String>`. O BM25F, que vem no passo 3, usa a *frequência do termo* em cada campo (tf): "prisão e prisão preventiva" deve pontuar mais para "prisao" do que um título que cita a palavra uma vez. Se o tokenizador devolvesse um conjunto, essa informação seria destruída antes de chegar ao índice, e não haveria como recuperá-la. Regra geral: perca informação o mais tarde possível. O teste `testPreservaRepeticoes` trava esse contrato.

**Indicadores ordinais º e ª.** Para o Unicode, "º" está na categoria Lo (Letter, other), então `Character.isLetter` é `true`. Sem tratamento, "5º" viraria o termo `5º` e nunca casaria com quem digita "5". `fazParteDeTermo` exclui os dois explicitamente, então "art. 5º" vira `["art","5"]`. É um exemplo de como categorias Unicode não coincidem com a intuição de quem fala português.

**Ponto entre dois dígitos não separa.** Esta foi uma mudança feita durante a implementação (o Ricardo foi avisado; é reversível). Antes, "Lei 8.078/90" daria `["lei","8","078","90"]` e quem digitasse "8078" não acharia. Agora o ponto, quando tem dígito dos dois lados (`pontoEntreDigitos`, com um `continue` que não fecha o termo), é engolido e dá `["lei","8078","90"]`. Quem digita "8078" ou "8.078" acha o livro, porque a consulta passa pelo mesmo caminho. Consequências aceitas:
- "1.2.3" vira `123`. Isso não atrapalha porque a numeração do sumário fica em `ItemSumario.numeracao`, que não é indexada, e o título fica limpo.
- Ponto no fim do número ("8.078. Comentários") continua separando, porque depois do segundo ponto vem espaço, e não dígito.
- Efeito colateral conhecido: "nº" vira o termo `n` (o "º" separa). Não foi tratado, porque `n` tem IDF baixo (aparece em muitos livros e pesa pouco).

**`enum` sem casos como namespace.** `enum Tokenizador { static func ... }` não pode ser instanciado, então não carrega estado e não é singleton. É o idioma do Swift para agrupar funções puras, e combina com a regra do projeto de "sem singletons". Uma função pura (mesma entrada, mesma saída, sem efeito colateral) é trivial de testar, e é isso que os 10 testes fazem.

### Por que assim
- **Pipeline único para índice e consulta**: garante que os dois lados falem a mesma língua.
- **Lista, e não conjunto**: o BM25F precisa do tf (veja acima).
- **Tratar º/ª e o ponto entre dígitos**: o público é jurídico, e "art. 5º" e "Lei 8.078/90" são os padrões mais comuns de busca.
- **`Set` para as palavras vazias**: consulta O(1) média.
- **Lista de palavras vazias curta**: só o que é claramente funcional em português. Cortar demais esconderia livros, e a perda seria silenciosa.

### Alternativas descartadas
- **Palavras vazias dentro de `Normalizacao`**: `Normalizacao.chave` também compara nomes de categoria (`NomeDeCategoria`). Ali "Direito do Trabalho" e "Direito Trabalho" precisam continuar DIFERENTES. Se a normalização removesse "do", as duas colapsariam na mesma chave e criariam uma duplicata falsa. Separação de responsabilidades: normalização *compara*, tokenizador *prepara para busca*.
- **Usar `NLTokenizer` / `String.components(separatedBy:)` / regex**: o `NLTokenizer` vem do framework NaturalLanguage, e o Domínio só importa Foundation. A passada manual é curta, previsível e testável sem depender de plataforma.
- **Devolver `Set<String>`**: perderia as repetições.
- **Deixar o ponto sempre separar**: "8.078" viraria dois termos e a busca por "8078" falharia.

### Decisões adiadas para o passo 5 (motor)
- **Prefixo enquanto o usuário digita** ("preve" achar "preventiva").
- **Plural e radical** ("prisão" × "prisões"). Exige stemming ou outra técnica; o tokenizador atual trata como termos distintos.
- **Consulta com OU × E**: "prisão preventiva" exige os dois termos, ou qualquer um? Isso muda a ordenação e o recall.

### Padrões e boas práticas
- **Funções puras no Domínio**: sem I/O, fáceis de testar. Quando NÃO usar o `enum` namespace: se a coisa tiver estado ou precisar ser trocada por um falso nos testes (aí vira protocolo + `struct`).
- **Testes de contrato com exemplos reais** (`"Lei 8.078/90"`), inclusive o teste de equivalência `termos("Lei 8.078/90") == termos("lei 8078/90")`, que documenta a promessa ao usuário.
- **Teste de borda**: entrada vazia, só pontuação e só palavras vazias devolvem `[]`.

### Armadilhas
- **Normalizar de um lado só**: se alguém indexar com o tokenizador e consultar com `Normalizacao.chave`, as buscas somem sem erro. Diagnóstico: um teste que indexa e busca o mesmo texto.
- **Classificação Unicode**: `isLetter`/`isNumber` incluem coisas inesperadas (º, ª, frações como "½", dígitos de outros alfabetos). Quando algo "não casa", imprima os escalares Unicode (`unicodeScalars`) em vez de confiar no que a tela mostra.
- **Hífen e apóstrofo**: aqui o hífen separa. Se um dia entrar um termo como "e-mail", ele vira `e` + `mail` (o `e` é removido). Aceito pelo domínio jurídico, mas vale saber.
- **Remover palavras vazias da CONSULTA**: se o usuário digitar só "de", a consulta fica vazia, e o motor precisa decidir o que devolver (tudo? nada?). Isso é do passo 5.

### Para ir além
- Manning, Raghavan e Schütze, *Introduction to Information Retrieval*, cap. 2 ("The term vocabulary and postings lists"): tokenização, stop words, normalização. Disponível online gratuitamente (nlp.stanford.edu/IR-book).
- Unicode Standard Annex #29 (Text Segmentation) e UAX #44 (categorias gerais, para entender Lo).
- Apple, documentação de `Character` e `String` (grapheme clusters) em *The Swift Programming Language*, capítulo "Strings and Characters".

### Perguntas
1. Com suas palavras: por que índice e consulta precisam passar exatamente pelo mesmo tokenizador? Dê um exemplo concreto de falha silenciosa se não passarem.
2. Aplicação: o que mudaria no resultado se o `Tokenizador` fosse reaproveitado para comparar nomes de categoria? Mostre um par de nomes que passaria a colidir. E, no outro sentido, o que mudaria se "nº" passasse a ser tratado como "numero": em que ponto do pipeline você colocaria essa regra?
3. Raciocínio (prepara o índice invertido e o BM25F): considere os títulos A = "prisão preventiva" e B = "prisão e prisão cautelar". (a) Escreva `termos` de cada um. (b) Se `termos` devolvesse um conjunto, o que A e B teriam de diferente para a palavra "prisao"? (c) Como você acha que um índice invertido (termo → lista de livros) deveria guardar a informação de repetição, para que o BM25F calcule a frequência por campo (título, autor, assunto) sem reler os textos? (d) Por que um termo que aparece em quase todos os livros deveria pesar menos no ranking?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

#### Correção das respostas
(sem respostas)

---

## Tarefa 2.3b — Índice invertido da busca (2026-10-09)

### O que foi feito
Criamos `Dominio/Busca/IndiceInvertido.swift`: um `struct` só com Foundation que guarda, em memória, tudo que o BM25F (passo 3, que o Ricardo vai escrever) precisa consumir. Junto vieram o enum `CampoBusca` e o tipo `ItemSumarioIndexado`. Os 18 testes estão em `EstantesTests/Dominio/Busca/IndiceInvertidoTests.swift` (suíte completa: 78 testes, 0 falhas no Xcode 14.2). O `PLANO.md` ganhou uma linha dizendo que o índice grava os nomes das categorias. Este é o passo 2 de 5 da tarefa 2.3.

### Conceitos envolvidos

**Índice comum x índice invertido.** Um índice comum mapeia livro → palavras: para achar "prisão" você abre todos os livros e procura. O invertido mapeia palavra → livros:

```
"prisao" → { A: 2× no título, C: 1× no sumário }
```

A busca só toca os livros das listas dos termos digitados. É a estrutura clássica de recuperação de informação (a mesma ideia do índice remissivo no fim de um livro, o motivo do nome "invertido").

**O que o índice guarda é o que o BM25F consome.** Esta foi a ideia que guiou o desenho: primeiro listamos o que a fórmula precisa, depois escolhemos a estrutura.

| Dado | Para quê no BM25F |
| --- | --- |
| tf por campo de cada livro | frequência ponderada por campo |
| tamanho de cada campo em cada livro | normalização por tamanho (`b`) |
| tamanho médio de cada campo na biblioteca | idem: compara o livro com a média |
| df (em quantos livros o termo aparece, em qualquer campo) | IDF |
| N (total de livros) | IDF |

**Campos (`enum CampoBusca`).** Título, subtítulo, autores, nomes das categorias, `cddirCaminho` e sumário (os títulos de todos os itens, tratados como um campo só). Editora, ano, estante e código CDDir são filtros (passo 4), então ficam fora do índice: não são texto a ranquear. Usamos `enum` e não `String` para o campo porque o compilador impede o campo escrito errado (`"titullo"` compilaria; `.titullo` não). Além disso, `CaseIterable` permite o teste `testTodoCampoBuscaEIndexado`: se alguém criar um campo novo e esquecer de indexá-lo em `adicionar`, o teste acusa.

**A estrutura por dentro.**

```mermaid
flowchart LR
  P["postings<br/>[String: [UUID: [CampoBusca: Int]]]"] 
  D["documentos<br/>[UUID: Documento]"]
  S["somaDosTamanhos<br/>[CampoBusca: Int]"]
  D --> T["tamanhos por campo"]
  D --> TS["Set dos termos do livro"]
  D --> I["itens do sumário tokenizados"]
```

- `postings`: termo → livro → campo → frequência. Só aparecem os campos onde o termo ocorre (daí o contrato "campo ausente vale 0, use `?? 0`").
- `documentos`: o que o índice sabe de cada livro (tamanhos por campo, o `Set` de termos e os itens do sumário já tokenizados).
- `somaDosTamanhos` por campo: a média é `soma / N`, calculada em O(1) sem recontar a biblioteca. Somas são fáceis de manter: soma ao adicionar, subtrai ao remover.

**Por que `remover` precisa do `Set` de termos.** Sem ele, para tirar um livro seria preciso varrer o vocabulário inteiro (todas as chaves de `postings`) procurando o id: O(V). Com o Set, visitamos só as entradas daquele livro: O(termos do livro). Ao remover, os termos que ficam sem nenhum livro são apagados, senão `quantidadeDeLivros(contendo:)` ficaria com entradas vazias e o vocabulário só cresceria.

**Idempotência de `adicionar`.** `adicionar` de um id existente remove a versão antiga antes. Assim "reindexar" é só chamar `adicionar` de novo, e é impossível contar um livro duas vezes por ter esquecido o `remover`. Foi um ajuste anunciado ao Ricardo antes de codar. É o mesmo princípio de um `upsert` no banco: a operação expressa a intenção ("este é o estado do livro agora"), não o passo mecânico.

**Médias contam campos vazios.** Um livro sem subtítulo entra na média do subtítulo com tamanho 0, como no BM25F clássico (a média é sobre todos os documentos da coleção). Se só contássemos quem tem subtítulo, a média ficaria inflada e livros normais pareceriam curtos demais.

**Itens do sumário guardados tokenizados.** Cada livro guarda uma lista de `ItemSumarioIndexado(id, frequencias, tamanho)`. O motivo: o PLANO diz que o item exibido no resultado é o de melhor nota BM25 *entre os itens daquele livro*. Com os itens já tokenizados, o motor roda um BM25 simples só sobre os itens dos livros que entraram no resultado, sem tokenizar de novo. Há também `tamanhoMedioDosItens` (soma e contagem de itens mantidas à parte).

**`struct` com métodos `mutating`.** O índice é um valor: `var indice = IndiceInvertido()`, e `adicionar`/`remover` o modificam. Isso combina com a regra "Domínio só com Foundation, sem singletons": o dono do índice (o motor, no passo 5) é quem guarda o valor. Detalhe: dicionários e arrays do Swift são copy-on-write, então copiar o `struct` é barato até alguém modificar uma das cópias.

**Complexidade.**
- `adicionar`: O(T) no total de termos do livro (mais o custo de remover a versão antiga, se existir).
- `remover`: O(termos do livro).
- `ocorrencias(de:)`, `quantidadeDeLivros(contendo:)`, `tamanho(de:noLivro:)`, `tamanhoMedio(de:)`: O(1) em média (tabelas hash).

### Por que assim
- **Índice invertido em vez de varrer**: com centenas de livros, varrer tudo a cada tecla digitada também seria rápido. O índice foi decisão do PLANO porque escala e porque é a estrutura clássica que o projeto quer ensinar.
- **Dicionário em memória**: simples, rápido, reconstruído ao abrir o app (decisão do PLANO).
- **Guardar o mínimo que o BM25F consome**: nada de dado "para o caso de precisar".
- **O índice grava nomes de categoria, não ids**: o texto é o que se pesquisa. Consequência: se a categoria for renomeada ou apagada, o índice fica velho. Essa obrigação é de quem usa o índice (documentada em `adicionar` e no `PLANO.md`); o teste dela vem no passo 5 (motor), onde existe quem a cumpra.
- **Itens do sumário como `ItemSumarioIndexado`**: evita retokenizar na busca.

### Alternativas descartadas
- **Varrer todos os livros a cada busca**: funcionaria no tamanho esperado, mas não é a estrutura que o projeto quer aprender e não escala.
- **Posting lists ordenadas por id, como no Lucene**: compensam em disco e com milhões de documentos (união/interseção por merge, compressão de deltas). Em memória, com poucos livros, o dicionário aninhado é bem mais simples.
- **Retokenizar o sumário na hora da busca**: desperdício; o trabalho já foi feito ao indexar.
- **Um segundo índice invertido só de itens do sumário**: exagero. Um BM25 simples só entre os itens dos livros do resultado basta.
- **Busca por prefixo, plural e OU x E no índice**: não afetam a estrutura. O prefixo, por exemplo, pode varrer as chaves do vocabulário na hora da consulta.

### Padrões e boas práticas
- **Projetar a estrutura a partir de quem a consome** (a tabela acima).
- **Invariantes mantidas por quem as quebra**: `adicionar` garante sozinho que não há duplicata. Evite APIs em que o chamador precisa lembrar da ordem certa de chamadas.
- **Encapsulamento**: `postings`, `documentos` e as somas são `private`; o mundo vê só consultas. Quando NÃO fazer isso: se uma estrutura fosse apenas um pacote de dados sem invariantes, `private` só atrapalharia.
- **Teste que protege invariante** (a lição da revisão): o único teste de remoção zerava tudo, então um erro na subtração das somas dos itens passaria. Testes de remoção devem deixar *outro* livro no índice e conferir que ele não mudou. Testes de idempotência (reindexar com conteúdo idêntico) pegam acumuladores que "vazam".

### Armadilhas
- **Item de sumário sem termos** (ex.: "De", só palavra vazia) tem tamanho 0 e conta na média. É a decisão registrada no teste `testItemDoSumarioSemTermosContaNaMedia`.
- **Divisão por zero no passo 3**: tamanho 0 de um livro é inofensivo (fica no numerador de `b · tamanho / média`). Mas a *média* 0 (por exemplo, uma biblioteca sem nenhum sumário, ou nenhum subtítulo) vira `0/0` na fórmula de normalização, o que dá `NaN`, e um `NaN` na soma estraga a nota do livro silenciosamente. A fórmula precisa tratar média 0.
- **Contrato do `ocorrencias`**: campo ausente no dicionário significa 0. Quem escrever `campos[.titulo]!` trava; use `?? 0`.
- **Acumuladores desalinhados**: se `adicionar` somar algo que `remover` não subtrai (ou o contrário), as médias derivam com o uso, e nenhum teste de um livro só percebe. Diagnóstico: adicionar, remover e reindexar em sequência e comparar com um índice novo montado do zero.
- **Nome de categoria velho**: veja "Por que assim".

### Para ir além
- Manning, Raghavan e Schütze, *Introduction to Information Retrieval*, cap. 1 (índice invertido) e cap. 6 (tf-idf e ranking). Online em nlp.stanford.edu/IR-book.
- Robertson e Zaragoza, *The Probabilistic Relevance Framework: BM25 and Beyond* (2009): a seção sobre BM25F explica por que se combinam as frequências dos campos antes da saturação.
- Documentação da Apple sobre `Dictionary` e `Set` na Swift Standard Library (custos e copy-on-write).

### Preparação para o passo 3 (BM25F, escrito por você)
Antes de escrever código, faça a conta à mão uma vez. Cenário pequeno, com a API do índice:

- Livro A: título "Prisão preventiva e prisão temporária", sumário `["Prisão em flagrante"]`.
- Livro B: título "Processo penal", sumário `["Prisão preventiva", "Recursos"]`.
- Livro C: título "Direito civil", sem sumário.

(Lembre: "e" e "em" são palavras vazias e somem na tokenização.) O que o índice responde:

| Chamada | Resultado |
| --- | --- |
| `totalDeLivros` | 3 |
| `quantidadeDeLivros(contendo: "prisao")` | 2 (A e B) |
| `ocorrencias(de: "prisao")` | A: título 2, sumário 1; B: sumário 1 |
| `tamanho(de: .titulo, ...)` | A = 4, B = 2, C = 2 |
| `tamanhoMedio(de: .titulo)` | 8/3 ≈ 2,667 |
| `tamanho(de: .sumario, ...)` | A = 2, B = 3, C = 0 |
| `tamanhoMedio(de: .sumario)` | 5/3 ≈ 1,667 |

Forma da fórmula (confira com o PLANO, que fixa a decisão de combinar os campos antes da saturação):

```
para cada campo c:  tf'_c = tf_c / (1 - b_c + b_c * tamanho_c / média_c)
tf_ponderado       = Σ_c  peso_c * tf'_c
nota do termo      = IDF * tf_ponderado / (k1 + tf_ponderado)
IDF (variante Lucene) = ln(1 + (N - df + 0.5) / (df + 0.5))
```

Valores só para este exercício (não são os do projeto): `peso_título = 3`, `peso_sumário = 1`, `b = 0,75` nos dois, `k1 = 1,2`. Para o termo "prisao":

- IDF = ln(1 + (3 - 2 + 0,5) / (2 + 0,5)) = ln(1,6) ≈ 0,470.
- Livro A: título → norma = 0,25 + 0,75 · 4/2,667 = 1,375, então tf' = 2/1,375 ≈ 1,455 e, com peso 3, ≈ 4,364. Sumário → norma = 0,25 + 0,75 · 2/1,667 = 1,15, então tf' ≈ 0,870. Soma ≈ 5,233. Saturação: 5,233 / (1,2 + 5,233) ≈ 0,814. Nota ≈ 0,470 · 0,814 ≈ 0,382.
- Livro B: só sumário → norma = 0,25 + 0,75 · 3/1,667 = 1,6, então tf' = 0,625. Saturação: 0,625 / 1,825 ≈ 0,342. Nota ≈ 0,161.
- Livro C: não aparece em `ocorrencias`, então nem é visitado.

Note como A vence: o termo está no título (peso alto) e repetido. Note também que a fórmula usa o tamanho do campo *no próprio livro* contra a média: B tem um sumário maior que a média e é penalizado.

Casos de borda que a sua função precisa tratar: média 0 (veja Armadilhas), termo que não existe no índice (df = 0: o IDF ainda é definido nessa variante, mas não há livros para visitar), e consulta com vários termos (some as notas dos termos de cada livro).

### Perguntas
1. Com suas palavras: qual é a diferença entre um índice comum e um invertido, e por que `remover` precisa guardar o `Set` de termos de cada livro? O que aconteceria sem ele?
2. Aplicação: o que mudaria no índice (e no código) se quiséssemos que a editora também fosse pesquisável por texto? E se uma categoria "Penal" fosse renomeada para "Direito Penal": quais chamadas o motor teria de fazer, e para quais livros?
3. Raciocínio (passo 3), no cenário A/B/C acima: (a) calcule, com os mesmos parâmetros do exemplo, a nota de A e de B para o termo "preventiva" (df = 2: A tem 1 no título, B tem 1 no sumário). Quem vence e por quê? (b) Se a biblioteca inteira não tivesse nenhum subtítulo, o que `tamanhoMedio(de: .subtitulo)` devolveria, e em qual ponto da fórmula isso quebraria? Proponha uma proteção. (c) Por que somamos os `tf'` dos campos *antes* de aplicar `k1`, em vez de calcular um BM25 por campo e somar as notas?

### Minhas respostas
(sem respostas)


## Tarefa 2.3c — Ranking BM25F (2026-10-09)

### O que foi feito
Foi criado `Dominio/Busca/BM25F.swift` com `ParametrosBM25F` (k1, pesos e `b` por campo, validados no `init`) e o `enum BM25F`, que calcula `idf`, `notas` (nota de cada livro para uma lista de termos) e `notaDoItem` (nota de um item do sumário, usada depois para escolher qual item mostrar no resultado). Os testes estão em `EstantesTests/Dominio/Busca/BM25FTests.swift` (14 testes; a suíte toda ficou em 92 testes, 0 falhas no Xcode 14.2). O `PLANO.md` registra o passo 6 da 2.3 (conjunto de consultas de referência) e a decisão de 09/10.

Nota sobre a divisão do trabalho: este passo estava marcado `[eu escrevo]`. O Ricardo pediu antes o enunciado completo (o porquê, como funciona, um exemplo simples) e, depois de lê-lo, pediu que o Claude escrevesse o BM25F e os testes. A marcação foi retirada do PLANO. Esta entrada existe para que você entenda a fundo um código que não escreveu; leia-a com o arquivo `BM25F.swift` aberto ao lado.

### Conceitos envolvidos

#### 1. Por que BM25F (a explicação dada ao Ricardo)

Todos os métodos abaixo respondem à mesma pergunta: dado um termo da consulta e um livro, quanto esse livro "merece" aparecer?

| Método | Como pontua | Problema |
| --- | --- | --- |
| Contar termos que casam | Nota = quantos termos da consulta aparecem no livro | Não distingue termo raro de comum ("direito" vale o mesmo que "flagrante"), nem título de sumário |
| TF-IDF linear | tf × idf: o IDF resolve raro × comum | Sem saturação: repetir "direito" 50 vezes ganha 50 vezes. Fácil de "enganar" por repetição |
| BM25 no texto concatenado | Junta todos os campos num texto só e aplica BM25 | Satura e normaliza o tamanho, mas perde os campos: título e sumário valem igual |
| Somar um BM25 por campo | Um BM25 por campo, soma das notas | Satura por campo: um termo presente em 6 campos chega a cerca de 6 vezes o máximo de um termo só. Descartado no PLANO |
| **BM25F** | Pondera os campos, normaliza o tamanho de cada um e satura **uma vez por termo** | É léxico: "prisões" não acha "prisão" (decisão no passo 5) |

#### 2. As três ideias do BM25F

**(a) IDF: o quanto o termo é raro.**

`IDF = ln(1 + (N − df + 0,5) / (df + 0,5))`

`N` é o total de livros e `df` é em quantos livros o termo aparece. É a variante do Lucene: o `1 +` dentro do logaritmo garante que o resultado seja sempre positivo. Na fórmula clássica, um termo presente em mais da metade dos livros dava IDF negativo (um termo comum "punia" o livro). Aqui o pior caso é perto de zero, nunca negativo.

**(b) Frequência combinada entre campos.**

`B_c = (1 − b_c) + b_c · tamanho / média`
`tf~ = Σ_c peso_c · tf_c / B_c`

`tamanho` é o número de termos do campo naquele livro; `média` é o tamanho médio desse campo na biblioteca. `B_c` vale 1 quando o campo tem tamanho médio, é maior que 1 para campos mais longos (diluem o termo) e menor que 1 para os mais curtos. O parâmetro `b` regula isso: `b = 0` desliga a normalização, `b = 1` a aplica por inteiro. O `peso_c` diz quanto cada campo importa (título 3, autor 0,5). A soma acontece **antes** de qualquer saturação.

**(c) Saturação, uma vez por termo.**

`nota = Σ_termos IDF · tf~ / (k1 + tf~)`

A fração `tf~/(k1 + tf~)` é sempre menor que 1 e cresce cada vez mais devagar. Como a saturação vem depois da soma dos campos, **cada termo contribui, no máximo, com o seu IDF**, não importa em quantos campos apareça. Esse é o ponto do "F" do BM25F.

```mermaid
flowchart LR
    A[tf por campo] --> B["divide por B_c<br/>(tamanho do campo)"]
    B --> C["multiplica pelo peso_c"]
    C --> D["soma dos campos = tf~"]
    D --> E["satura: tf~ / (k1 + tf~)"]
    E --> F["multiplica pelo IDF"]
    F --> G["soma dos termos = nota do livro"]
```

#### 3. O exemplo à mão (k1 = 1,2; título peso 3, b 0,5; sumário peso 1, b 0,75)

| Livro | Título (termos) | Sumário (termos) |
| --- | --- | --- |
| A | "Prisão preventiva" (2) | "Prisão em flagrante" (2; "em" é palavra vazia) |
| B | "Processo penal" (2) | "Prisão", "Recursos", "Provas" (3 itens, 3 termos) |
| C | "Direito civil" (2) | "Contratos" (1) |

N = 3. Média do título = (2+2+2)/3 = 2. Média do sumário = (2+3+1)/3 = 2.

**Termo "prisão"** (df = 2, aparece em A e B): IDF = ln(1 + 1,5/2,5) = ln 1,6 = **0,4700**.

| Livro | Cálculo de tf~ | Saturação | Nota |
| --- | --- | --- | --- |
| A | título: B = 1, 3·1/1 = 3; sumário: B = 1, 1·1/1 = 1; tf~ = **4** | 4/5,2 = 0,7692 | 0,4700 · 0,7692 = **0,3615** |
| B | só sumário: B = 0,25 + 0,75·(3/2) = 1,375; tf~ = 1/1,375 = 0,7273 | 0,7273/1,9273 = 0,3774 | 0,4700 · 0,3774 = **0,1774** |
| C | não aparece em `ocorrencias`, nem é visitado | | (fora) |

**Consulta "prisão flagrante"**: "flagrante" aparece só em A (df = 1), IDF = ln(1 + 2,5/1,5) = ln(8/3) = **0,9808**. No sumário de A, tf~ = 1 (B = 1), saturação 1/2,2 = 0,4545, contribuição 0,9808 · 0,4545 = 0,4458. Nota de A = 0,3615 + 0,4458 = **0,8074**. B continua em 0,1774. A vence com folga porque casa os dois termos, e o raro vale mais.

**Contraste com saturar por campo.** Se "prisão" em A fosse saturada em cada campo e depois somada: título 3/(1,2+3) = 0,714 e sumário 1/(1,2+1) = 0,455, total **1,17** (antes de multiplicar pelo IDF), contra **0,77** do BM25F. É a inflação que o PLANO quis evitar.

**Saturação na prática.** Se tf~ passasse de 4 para 8 (o dobro), a fração iria de 0,77 para 0,87. Não dobra: 8/9,2 = 0,87.

**Nota do item.** Há 5 itens no total (A: 1, B: 3, C: 1) e 6 termos entre eles, então a média dos itens é 6/5 = 1,2. O item único de A tem 2 termos: fator = 0,25 + 0,75·(2/1,2) = 1,5; tf~ = 1/1,5 = 0,6667; saturação 0,6667/1,8667 = 0,357; nota 0,4700 · 0,357 = **0,1679**. Os números calculados à mão bateram com o código.

#### 4. Os padrões escolhidos e as proteções

| Campo | Peso | b | Raciocínio |
| --- | --- | --- | --- |
| título | 3 | 0,5 | o que o usuário mais lembra |
| subtítulo | 2 | 0,5 | complementa o título |
| categorias | 1,5 | 0,3 | rótulo curto, escolhido pelo usuário |
| cddirCaminho | 1,5 | 0,3 | rótulo curto da classificação |
| sumário | 1 | 0,75 | campo longo: o tamanho mais distorce a contagem |
| autores | 0,5 | 0 | o tamanho de um nome não indica relevância |

`k1 = 1,2`. Estes são pontos de partida, e serão ajustados no passo 6.

Proteções no código (releia `BM25F.swift`):
- `fatorDeTamanho`: se a média é 0, devolve 1 (evita o `0/0` que a entrada 2.3b previu como armadilha).
- `saturar(0) = 0`: com `k1 = 0` e `tf = 0`, a fração seria `0/0 = NaN`. O `guard tf > 0` evita isso.
- Iterar só os campos onde o termo tem `tf > 0` (`guard let tf = frequencias[campo]`) garante que `tamanho > 0` e `média > 0` naquele campo, logo o fator nunca é 0/0. Não precisa checar de novo.

#### 5. O que acontece nos extremos de k1 (para você prever o comportamento)

`saturar(tf) = tf/(k1 + tf)`:
- **k1 → 0**: a fração tende a 1 para qualquer tf > 0. A nota vira "casou ou não": cada termo vale exatamente o seu IDF, não importa quantas vezes apareça. O teste `testExtremosValidosDosParametrosDaoNotaFinita` trava isso (B = 0,4700 e A = 0,4700 + 0,9808).
- **k1 → ∞**: o denominador é dominado por k1, a fração vira aproximadamente `tf/k1`, ou seja, **linear em tf~**. Volta o problema do TF-IDF linear (repetir ganha proporcionalmente).
- k1 típico (1,2 a 2) fica no meio: sobe rápido nas primeiras ocorrências e achata.

#### 6. Ordem de soma e determinismo

`Set` e `Dictionary` do Swift usam hash com semente aleatória por processo, então a ordem de iteração muda de uma execução para outra. Soma de `Double` **não é associativa**: em ponto flutuante, `(0,1 + 0,2) + 0,3` dá `0,6000000000000001`, mas `0,1 + (0,2 + 0,3)` dá `0,6`. Diferenças na última casa decimal podem mudar quem fica na frente num desempate, e o bug seria intermitente (passa num teste, falha no seguinte). A correção foi somar sempre em ordem fixa: `Set(termos).sorted()` para os termos e `CampoBusca.allCases` para os campos. Observação: a iteração sobre `ocorrencias` (um dicionário por livro) não afeta o resultado, porque cada livro acumula em chave própria; só importa a ordem das somas dentro do mesmo livro.

### Por que assim
- **`BM25F` como `enum` sem casos, só `static func`**: é uma função pura, sem estado. Um `struct` instanciável não acrescentaria nada, e `enum` impede criar instâncias por engano. O estado (contagens, médias) já mora no `IndiceInvertido`.
- **`ParametrosBM25F` como struct com `let` e `init` com `precondition`**: parâmetros fora de faixa (k1 negativo, b > 1, peso negativo) fazem a fórmula dividir por zero ou dar nota negativa. Validar na criação faz o erro aparecer no ponto onde o valor errado nasce, e `let` impede alterar depois e contornar a validação. Observação para prever: `precondition` continua ativo em builds -O (Release); só `assert` some. Um `NaN` também é barrado, porque `NaN >= 0` e `(0...1).contains(.nan)` são falsos.
- **Parâmetros injetáveis com padrão `.padrao`**: o passo 6 precisa trocar pesos e medir o efeito; os testes também precisam de valores próprios (`testCadaCampoUsaOProprioPesoEB`).
- **`notaDoItem` usa o IDF do livro inteiro**: o IDF é uma propriedade do termo na biblioteca, não do item; usar a mesma raridade mantém item e livro coerentes. Só `tf`, `k1`, `b` do sumário e a média dos itens mudam.
- **Livro com termo só em campo de peso 0 entra com nota 0**: é consequência direta da fórmula (peso 0 zera tf~). Foi documentado, e o motor (passo 5) decide se o mostra.
- **Pesos ajustados por conjunto de consultas de referência (passo 6), não olhando o app**: ver "Alternativas descartadas".

### Alternativas descartadas
- **Um BM25 por campo, somado**: infla notas de termos presentes em muitos campos (ver tabela). Descartado no PLANO.
- **BM25 no texto concatenado**: perde a ponderação por campo.
- **Ajustar os pesos só testando o app**: poucos casos, o julgamento é "parece bom", e consertar uma busca pode piorar outras sem ninguém ver. O método escolhido: 20 a 30 fichas reais (da estante do Ricardo ou do LexML com descrição/sumário), 15 a 20 consultas, cada uma com o livro esperado, e uma métrica calculada num teste XCTest. As métricas: **top 1** (o esperado é o primeiro?), **top 3** (está entre os três primeiros?) e **MRR** (*mean reciprocal rank*, a média de 1/posição do livro esperado; 1º vale 1, 2º vale 0,5, 3º vale 0,33...). Mudar um peso mostra o efeito em todas as consultas de uma vez. Será feito **depois do motor** (passo 6), porque o que se mede é o motor inteiro (normalização, filtros, desempate), não só a fórmula. O app (2.7) só confere a sensação de uso e sugere consultas novas para o conjunto. O mesmo método está previsto para a Fase 3. Registrado na tabela de decisões do PLANO (09/10).
- **Lematização/stemming para "prisões" achar "prisão"**: fora do escopo da fórmula; a decisão fica para o passo 5.
- **Cálculo de `Σ` tolerante a pesos negativos**: rejeitado em favor de impedir o valor inválido na criação.

### Padrões e boas práticas
- **Função pura + injeção de parâmetros**: facilita testar e ajustar. Quando não usar: se a função precisasse de estado entre chamadas (cache de IDFs, por exemplo), um tipo com estado seria mais adequado; aqui seria otimização prematura.
- **Validação de invariantes no `init` (fail fast)** com `precondition`. Quando não usar: para entrada vinda do usuário ou da rede, não se deve travar o app; aí o `init` deveria ser falível (`init?`) ou lançar erro. Aqui os valores vêm do código, então um valor inválido é erro de programação.
- **Teste com exemplo calculado à mão**: trava os números reais. Os testes de desigualdade (`GreaterThan`) travam propriedades (mais curto vence, repetição não dobra) e são complementares, não substitutos. A revisão sugeriu trocá-los por números e a sugestão foi rejeitada por esse motivo.
- **Testes que percorrem `allCases`**: se um campo novo entrar no enum, o teste o cobre sozinho (ou falha o `switch`, que precisa ser exaustivo).
- **`private lazy var` em `XCTestCase`**: seguro, porque o XCTest cria uma instância da classe por método de teste; `lazy` é necessário porque o inicializador usa `self` (`estanteId`).

### Armadilhas
- **Ordem de soma não determinística** (item 6 acima): bug intermitente na última casa decimal. Diagnóstico: rodar o mesmo teste várias vezes e comparar com `==` em vez de `accuracy`.
- **Nome de variável igual ao do método auxiliar** (`var indice = indice([...])`): compila, mas é frágil e confunde a leitura. Por isso o auxiliar se chama `montarIndice` e os livros `livroA/B/C`.
- **Média 0 e `tf = 0`**: `NaN` silencioso na nota; o `NaN` contamina a soma e some do radar. Diagnóstico: `XCTAssertTrue(nota.isFinite)`.
- **Nota 0 não é "sem resultado"**: um livro pode entrar com nota 0 (campos de peso 0). Quem consumir `notas` não pode assumir que todo valor é positivo.
- **Termos repetidos na consulta** contam uma vez (por causa do `Set`); se isso não fosse desejado, o comportamento mudaria.
- **Parâmetros ajustados no escuro**: mexer num peso sem medir é o erro que o passo 6 existe para evitar.

### Para ir além
- Robertson e Zaragoza, *The Probabilistic Relevance Framework: BM25 and Beyond* (2009): a seção de BM25F é a base do que foi implementado aqui.
- Manning, Raghavan e Schütze, *Introduction to Information Retrieval*, cap. 6 (ranking) e cap. 8 (avaliação: precisão, MRR). Online em nlp.stanford.edu/IR-book.
- Documentação do Swift sobre `precondition` e sobre `Set`/`Dictionary` (ordem de iteração não especificada). Para os números de ponto flutuante: Goldberg, *What Every Computer Scientist Should Know About Floating-Point Arithmetic*.

### Perguntas
1. Com suas palavras: o que a fórmula `tf~/(k1 + tf~)` faz com o valor de `tf~`? Explique por que ela precisa ser aplicada **depois** de somar os campos, e o que aconteceria se fosse aplicada em cada campo antes da soma (use o contraste 1,17 contra 0,77 do exemplo).
2. Aplicação: (a) o que acontece com a nota de cada termo se `k1 → 0`? E se `k1 → ∞`? Em qual dos dois a repetição de um termo conta mais? (b) Por que o `init` de `ParametrosBM25F` valida, e por que as propriedades são `let`? Que valor de entrada levaria a uma divisão por zero ou a uma nota negativa?
3. Raciocínio: (a) por que o código itera `Set(termos).sorted()` e `CampoBusca.allCases` em vez de `Set(termos)` e `parametros.pesos.keys`? Dê um exemplo concreto de dois resultados diferentes da mesma soma de `Double`. (b) Refaça à mão a nota de B para "prisão" se o `b` do sumário fosse 0 (B deixa de ser penalizado por ter 3 itens). A nota sobe ou desce em relação a 0,1774? (c) As perguntas da 2.3b (calcular à mão o "preventiva" no cenário A/B/C e a proteção para média 0) continuam valendo: o código agora mostra a resposta de (b) dessa entrada em `fatorDeTamanho`.

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

**Correção das respostas:** (sem respostas)

---

## Tarefa 2.3d — Filtros da busca (2026-10-09)

### O que foi feito
Criei `Dominio/Busca/FiltroBusca.swift`: uma `struct` só com Foundation que guarda as escolhas das chips (autor, editora, faixa de anos, estantes, prefixo de CDDir, categorias) e expõe o predicado puro `aceita(_ livro:) -> Bool` e `estaVazio`. Os testes estão em `EstantesTests/Dominio/Busca/FiltroBuscaTests.swift`. A suíte ficou em 112 testes, 0 falhas, no Xcode 14.2. O PLANO marcou os passos 3 e 4 da 2.3 e ganhou uma linha na tabela de decisões.

### Conceitos envolvidos

#### 1. Predicado puro e filtro vazio
Um predicado é uma função `Livro -> Bool`. Ele é "puro" porque a resposta depende só do filtro e do livro, sem rede, relógio nem estado escondido. Isso permite testar com exemplos pequenos e reaproveitar o filtro no motor, na tela e em testes. Regra de identidade: o filtro vazio aceita tudo, como o `true` do `&&`.

#### 2. Lógica E entre dimensões, OU dentro de uma dimensão
```mermaid
flowchart LR
  L[Livro] --> A{autor?}
  A -->|passa| E{editora?}
  E -->|passa| N{ano?}
  N -->|passa| S{"estante ∈ conjunto?"}
  S -->|passa| C{CDDir?}
  C -->|passa| G{"categorias ∩ conjunto ≠ ∅?"}
  G -->|passa| OK[aceito]
```
Entre dimensões vale E (cada `if ... return false` é uma barreira). Dentro de estantes e categorias vale OU: `estanteIds.contains(livro.estanteId)` e `!categoriaIds.isDisjoint(with:)`. `Set.contains` é O(1) em média; `isDisjoint(with:)` percorre o menor dos dois conjuntos.

#### 3. "Sem filtro" por convenção: nil, texto em branco, conjunto vazio
Cada dimensão tem um valor neutro. Isso evita um `enum` de "ligado/desligado" por chip, mas cria um risco: a regra "em branco = sem filtro" precisa ser a mesma em `estaVazio` e em `aceita`. Se uma dimensão nova entrar em um lugar e não no outro, o motor (que usará `estaVazio` como atalho) pularia um filtro ligado. O teste de propriedade (ver "Padrões") amarra as duas funções.

#### 4. Autor: casamento por prefixo de termos, em qualquer ordem
O problema: o dado vem como "Silva, José Afonso da" e o usuário digita "José Afonso Silva". Comparar o texto inteiro ("contém") falha. A solução usa o `Tokenizador` da 2.3a: o nome vira termos normalizados (`["silva","jose","afonso"]`, porque "da" é palavra vazia), e cada termo digitado precisa ser prefixo de algum termo do **mesmo** autor:
```swift
termosProcurados.allSatisfy { procurado in
    termosDoNome.contains { $0.hasPrefix(procurado) }
}
```
Complexidade: O(p · t) por autor (p termos procurados, t termos do nome), pequenos de verdade. Consequências:

| Digitado | Resultado | Por quê |
| --- | --- | --- |
| "silv" | acha | prefixo de "silva" |
| "ilva" | não acha | meio da palavra, não prefixo |
| "da" | filtro conta como vazio | palavra vazia, o tokenizador descarta |
| "antonio grinover" | não casa com Cintra, Antônio + Grinover, Ada | os termos têm de estar no mesmo autor |

O "mesmo autor" está em `livro.autores.contains(where: { autor($0, casaCom:) })`: o OU é entre autores do livro, o E é entre os termos dentro de um autor.

#### 5. Editora, ano e CDDir
- **Editora**: `Normalizacao.chave` (minúsculas, sem acento) nos dois lados e `contains`. Editora não tem ordem de nome, então o "contém" basta.
- **Ano**: limites inclusivos e opcionais. Livro sem ano sai quando há qualquer limite (não dá para afirmar que está na faixa). Faixa invertida (mínimo > máximo) não aceita ninguém.
- **CDDir**: `hasPrefix` depois de remover todo espaço. A classificação decimal é hierárquica: "341.1" é o assunto geral, "341.12" um subassunto, então prefixo de string coincide com a hierarquia. Armadilha da string: "34" também pega "341" e "3412", o que aqui é desejado, mas um prefixo de "341.1" não pega "341.2".

#### 6. Onde o filtro entra no pipeline
O filtro roda **depois** do BM25F, sobre os candidatos já pontuados. O IDF (raridade do termo) é calculado sobre a biblioteca inteira no índice; se filtrássemos antes, o IDF mudaria com o conjunto e o mesmo livro teria nota diferente ao ligar uma chip. Custo: O(n) linear nos candidatos (n pequeno: biblioteca pessoal).

### Por que assim
As decisões, numeradas como foram aprovadas:
1. **`struct FiltroBusca` com estado**, diferente do `BM25F` (enum sem casos, função pura sem estado). O filtro guarda as escolhas da tela, então precisa de valores; o BM25F só calcula. Filtro vazio aceita tudo.
2. **Campos**: autor, editora (`String?`), anoMinimo, anoMaximo (`Int?`), estanteIds, categoriaIds (`Set<UUID>`), prefixoCDDir (`String?`). `nil`, texto em branco e conjunto vazio significam "sem filtro". Esses dados ficaram fora do `CampoBusca` na 2.3b justamente para serem filtros, não texto pontuado.
3. **E entre dimensões; OU dentro de estantes e categorias.** Marcar "Penal" e "Processo" mostra livros de qualquer uma. E entre categorias foi descartado: quem marca duas chips quase sempre quer ampliar.
4. **Editora** por `Normalizacao.chave` + "contém". **Autor** começou como "contém" no texto inteiro; o revisor apontou que "José Afonso Silva" não acha "Silva, José Afonso da". A busca BM25F (campo autores tokenizado) já acha em qualquer ordem, só o filtro falhava. Opções: (a) comparar por termos do `Tokenizador`, cada termo digitado prefixo de algum termo de um mesmo autor; (b) manter e a tela 2.7 oferecer lista de autores. Ricardo escolheu (a). Consequências na tabela acima.
5. **Ano**: limites inclusivos e opcionais; livro sem ano sai quando há filtro de ano; faixa invertida não aceita nenhum, **sem `precondition`**. Entrada do usuário não pode travar o app (lição da 2.3c: `precondition` é para erro de programação, como os parâmetros do BM25F). A tela evita o caso.
6. **CDDir**: `hasPrefix` depois de tirar **todos** os espaços (pontas e meio: "341 .2" vira "341.2"; código CDDir não tem espaço significativo). A hierarquia decimal faz "341.1" pegar "341.12". Livro sem CDDir sai.
7. **O filtro roda depois do BM25F** (no motor, passo 5), pelo motivo do IDF. Consulta vazia + filtro preenchido fica para o passo 5.
8. **Custo O(n) linear**; índices por faceta (bitmaps) descartados como otimização prematura.

### Alternativas descartadas
- **Filtrar antes do ranking**: mudaria o IDF e as notas (ver acima). Só valeria se o objetivo fosse "ranquear dentro do subconjunto" como uma biblioteca nova.
- **E entre categorias**: restringe demais; contraria a intenção típica de quem marca várias chips.
- **Autor por "contém" no texto inteiro**: falha com a ordem "Sobrenome, Nome" (achado 4 da revisão).
- **Opção (b) para autor** (lista de autores na tela 2.7): empurra o problema para a interface e não ajuda quem digita livremente.
- **`precondition` na faixa de anos invertida**: travaria o app por entrada do usuário.
- **Índices por faceta/bitmaps**: complexidade sem medida que a justifique.

### Padrões e boas práticas
- **Predicado puro com valor neutro (identidade)**: filtro vazio = `true`. Quando não usar: se o filtro precisasse de dados externos (consultar o banco por categoria), deixaria de ser puro e iria para a camada de dados.
- **Teste de propriedade amarrando duas funções** (`testCadaDimensaoLigadaDeixaDeEstarVazioERecusaLivro`): um filtro por dimensão (7, conferido com `count` para o teste falhar se uma dimensão nova for esquecida), exigindo `estaVazio == false` e recusa do livro. Isso fecha o risco de `estaVazio` e `aceita` divergirem.
- **Testar o E uma dimensão por vez**: dicionário de closures `(inout FiltroBusca) -> Void`, cada uma estraga uma dimensão de um filtro que antes aceitava o livro. Pegaria uma troca de E por OU.
- **Nomes que dizem o papel** (Swift API Design Guidelines): `textoNormalizado`, `editoraProcurada`, `prefixoProcurado` em vez de nomes sombreados (um método `static chave` com `let chave` dentro; `if let autor` sombreando a propriedade). Sombrear compila, mas confunde a leitura.
- **`guard` dentro do `if`** nas dimensões ano/CDDir: deixa explícito o caso "livro sem ano/sem cddir". A revisão apontou a mistura de estilos, e a mistura foi mantida de propósito.
- **Faixa de anos inclusiva** com comentário de teste mostrando que 2014 está entre 2010 e 2020 mas mesmo assim sai na faixa invertida: o teste documenta o porquê.

### Armadilhas
- **Closures guardadas num dicionário são `@escaping`**: dentro de um `XCTestCase`, acessar propriedades exige `self.` explícito no Swift 5.7 (`self.estante2`); sem isso o compilador reclama de captura implícita.
- **`estaVazio` e `aceita` divergirem**: diagnóstico pelo teste de propriedade; sintoma no app seria uma chip ligada sem efeito.
- **Filtro só com "da"** vira vazio (palavra vazia): o usuário digita e nada muda. É consistente com o tokenizador, mas pode surpreender na tela.
- **"ilva" não acha "Silva"**: prefixo não é substring. Aceito por escolha.
- **Livro sem ano/CDDir some quando o filtro está ligado**: correto, mas na tela convém explicar.
- **Termos do filtro recalculados a cada livro** (normalização e tokenização do texto procurado): custo pequeno hoje, adiado ao passo 5 (pré-calcular uma vez por consulta, só depois de medir).
- **Passo 5**: conferir que o motor aplica o filtro depois do BM25F e que usa `estaVazio` só como atalho.

### Para ir além
- Manning, Raghavan e Schütze, *Introduction to Information Retrieval*, cap. 1 e 7 (combinação de restrições booleanas com ranking); online em nlp.stanford.edu/IR-book.
- Swift API Design Guidelines (swift.org/documentation/api-design-guidelines): seção sobre clareza e nomes que dizem o papel.
- Documentação do Swift sobre closures: "Escaping Closures" em *The Swift Programming Language*.

### Perguntas
1. Com suas palavras: por que "José Afonso Silva" acha "Silva, José Afonso da" no filtro agora, mas "antonio grinover" não casa com um livro de Cintra, Antônio e Grinover, Ada? Onde no código está a diferença entre "o mesmo autor" e "qualquer autor do livro"?
2. Aplicação: se o produto pedisse que marcar as categorias "Penal" e "Processo" mostrasse só livros que têm **as duas**, o que mudaria em `aceita`? E o que mudaria no teste de propriedade e na tela, sabendo que `estaVazio` ainda precisa fazer sentido?
3. Raciocínio: suponha que o filtro de estante rodasse **antes** do BM25F, restringindo o índice às estantes marcadas. Dê um exemplo concreto com duas estantes e um termo (por exemplo "prisão") em que o mesmo livro mudaria de nota ao ligar a chip, e explique por quê usando o IDF. Depois diga: o `Tokenizador` ignora "da"; o que `FiltroBusca(autor: "da")` devolve em `estaVazio` e em `aceita`?

### Minhas respostas
(sem respostas)

---

## Tarefa 2.3e — Motor de busca (passo 5a) (2026-10-09)

### O que foi feito
Criei `Dominio/Busca/MotorDeBusca.swift`, que junta o `IndiceInvertido`, o `BM25F` e o `FiltroBusca` numa única API (`buscar`), e `ResultadoBusca.swift`. Acrescentei `IndiceInvertido.termos(comPrefixo:)` e refatorei `FiltroBusca` para ter a forma `Preparado`. Testes em `EstantesTests/Dominio/Busca/MotorDeBuscaTests.swift`; suíte em 131 testes, 0 falhas, Xcode 14.2. O passo 5 foi dividido: este é o **5a (motor)**; o **5b** traz o item do sumário no resultado e `atualizar(categorias:)` reindexando os livros afetados.

### Conceitos envolvidos

#### 1. O pipeline da consulta
```mermaid
flowchart LR
  T[texto] --> K[Tokenizador]
  K --> B["BM25F na biblioteca inteira<br/>(último termo: prefixo)"]
  B --> E["E: só quem tem todos os termos"]
  E --> F["filtro preparado"]
  F --> O["ordenar: nota, título, id"]
```
Cada etapa existe por um motivo. O BM25F roda antes do filtro porque o IDF depende do conjunto de livros (ver 2.3d). O E vem antes do filtro só por clareza; a ordem entre os dois não muda o resultado, só o custo.

#### 2. Struct com `mutating` em vez de classe
`MotorDeBusca` é um tipo-valor. `atualizar` e `remover` são `mutating`, e `buscar` não é (só lê). Em Swift, `let motor` impede mutação, `var motor` permite: o compilador diz quem pode alterar. O dono será o ViewModel (`@Published var motor`), sem singleton, como pede a arquitetura. Dicionários e arrays são copy-on-write: copiar o motor é barato até alguém alterar uma das cópias.

#### 3. Por que o motor guarda os livros
O índice só tem termos de texto (título, autores, categorias, sumário). O filtro precisa de editora, ano, estante e CDDir, que ficaram de fora do índice de propósito (2.3b). Então o motor mantém `[UUID: Livro]`: o índice responde "quem contém o termo", o dicionário responde "quem é esse livro" em O(1).

#### 4. E entre os termos, e o laço que o implementa
`BM25F.notas(termos: [t])` devolve só os livros que contêm `t`. Começamos com as notas do último termo e, para cada termo fixo, mantemos apenas os ids presentes em `notasDoTermo`, somando a nota:
```swift
for (id, nota) in notas {
    notas[id] = notasDoTermo[id].map { nota + $0 }   // nil remove a chave
}
```
Atribuir `nil` a uma chave de dicionário a remove. O `for` percorre uma **cópia** de `notas` (tipo-valor, copy-on-write: a primeira mutação dentro do laço duplica o armazenamento), por isso alterar o dicionário no laço é seguro. Em Swift, `Optional.map` aplica a função só se houver valor: `nil.map { ... }` continua `nil`. Complexidade: O(k · m), com k termos e m livros candidatos do último termo.

#### 5. Prefixo no último termo
O usuário ainda está digitando, então "prevent" deve achar "preventiva". Só o último termo expande, e só com 2 ou mais caracteres (com 1 letra, quase todo o vocabulário entraria). `termos(comPrefixo:)` filtra as chaves de `postings` com `hasPrefix` e ordena: O(V) mais a ordenação dos casados. Para cada expansão calculamos a nota e o livro fica com a **maior**, não a soma: um prefixo com muitas expansões não deve inflar a nota (a mesma ideia da saturação do BM25F). Consequência: como cada expansão traz seu IDF, costuma vencer a expansão mais rara na biblioteca.

#### 6. Ordenação determinística e "decorate-sort-undecorate"
O comparador precisa normalizar o título (`Normalizacao.chave`), operação cara. Uma ordenação faz O(n log n) comparações; normalizar dentro do comparador repete o trabalho. Em vez disso, `ordenar` calcula uma vez por resultado uma tupla `(resultado, tituloNormalizado, id)`, ordena as tuplas e descarta a decoração. É a **transformada de Schwartz** (decorate-sort-undecorate): O(n) normalizações em vez de O(n log n). Critérios: nota decrescente, título crescente, `uuidString` crescente. O último garante que duas execuções deem a mesma ordem, mesmo com notas e títulos iguais (o `sorted` do Swift não é garantidamente estável).

#### 7. `FiltroBusca.Preparado`
Antes, `aceita` normalizava a editora, tokenizava o autor e removia espaços do CDDir **a cada livro**. `preparado()` faz isso uma vez por consulta e devolve um valor com os textos já prontos; `estaVazio` e `aceita` de `FiltroBusca` só delegam. Efeito colateral bom: a regra "em branco = sem filtro" agora está num único lugar (`preparado()`), o que fecha o achado 1 da 2.3d.

### Por que assim
As decisões, numeradas como foram aprovadas (elas fecham as "decisões adiadas para o passo 5" da 2.3a e o achado 2 da revisão da 2.3d):
1. **`struct MotorDeBusca`** com `IndiceInvertido`, `[UUID: Livro]` e os nomes das categorias; `init(livros:categorias:)`, `atualizar(_:)`, `remover(livroId:)`, `buscar(_:filtro:parametros:)`. Struct com `mutating` porque o dono é o ViewModel, sem singleton. Guarda os livros porque o filtro precisa de editora, ano, estante e CDDir.
2. **`ResultadoBusca` = livro + nota** (o item do sumário vem na 5b). O nome da estante não entra: a tela resolve por `livro.estanteId`; senão renomear uma estante exigiria reindexar.
3. **E entre os termos.** "prisão" aparece em dezenas de livros jurídicos, e OU devolveria uma lista cheia de ruído. Custo: um erro de digitação zera o resultado. O passo 6 mede; se for frequente, a saída é "E, e se vazio, OU".
4. **Prefixo só no último termo**, mínimo 2 caracteres, **maior nota entre as expansões**. `termos(comPrefixo:)` varre o vocabulário em O(V).
5. **Plural/stemming adiado** ("prisão" × "prisões", algoritmo RSLP): o prefixo não resolve ("prisoes" não começa com "prisao"). Medir no passo 6; sinônimos na Fase 5.
6. **Consulta vazia** (em branco ou só palavras vazias, como "de"): sem filtro devolve `[]`; com filtro devolve os livros filtrados em ordem de título, nota 0.
7. **Ordem**: tokenizar, BM25F na biblioteca inteira, E, filtro (depois, para não mudar o IDF), ordenar. `FiltroBusca` ganhou `Preparado`.
8. **Ordenação**: nota decrescente, título normalizado crescente, id (`uuidString`), mantendo o determinismo da 2.3c.

Detalhe do E: `BM25F.notas` é chamado um termo por vez e a soma segue ordem fixa (último termo, depois os fixos em ordem alfabética). Soma de `Double` não é associativa, então a ordem pode mudar o último bit da nota; ordem fixa dá resultado reprodutível.

### Alternativas descartadas
- **OU entre os termos**: ruído demais em um domínio de vocabulário repetitivo.
- **Vocabulário ordenado + busca binária para prefixo**: acharia o intervalo em O(log V + r), mas manter o vocabulário ordenado custa a cada inclusão de livro. Só se a medição pedir.
- **Somar as notas das expansões do prefixo**: um prefixo curto como "pr" inflaria a nota de quem casa com várias palavras.
- **Nome da estante dentro do resultado**: obrigaria a reindexar ao renomear.
- **Remover o `.sorted()` de `termos(comPrefixo:)`** (sugestão da revisão, recusada): o custo é desprezível e a ordem fixa evita o bug intermitente da soma (ver acima).
- **Stemming agora**: sem medir, é complexidade especulativa.

### Padrões e boas práticas
- **Decorate-sort-undecorate**: use quando a chave de ordenação é cara de calcular. Não use quando a chave já é um campo guardado (ordenar por `nota` direto).
- **Preparar uma vez, usar muitas** (o `Preparado`): separar "interpretar a configuração" de "aplicá-la" evita trabalho repetido em laços. Não vale para filtros usados uma vez só.
- **Fonte única de verdade**: a regra "em branco = sem filtro" mora em `preparado()`; `FiltroBusca.estaVazio` e `aceita` apenas delegam.
- **Teste que distingue a versão certa da errada**: todo teste precisa de um caso em que o código errado daria resultado diferente.
- **Ler a falha antes de consertar**: o teste também pode estar errado.

### Armadilhas
- **O bug "penal penal"**: o último termo repetia um anterior e entrava duas vezes: nota 1,72 = 2 × 0,86. Correção: `anteriores.remove(ultimo) != nil` marca o repetido; repetido não expande (o usuário já passou dele) e conta uma vez só, como os repetidos no BM25F. `Set.remove` devolve o elemento removido (ou `nil`), então serve de teste de pertinência e remoção num só passo.
- **Teste que não protegia a correção**: "penal penal" passava mesmo sem o conserto, porque nada mais começa com "penal". O novo teste usa "prev" (acha A e D) e "prev prev" (devolve `[]`: o repetido vale como exato e "prev" não é um termo do vocabulário). Sem a correção, "prev prev" acharia A e D.
- **Erro do teste, não do motor**: esperei que "preve" achasse só "Prisão preventiva", mas "Prevenção" vira "prevencao" e também começa com "preve". Troquei por "prevent". Sintoma de diagnóstico: o motor retornava um livro "a mais" que, ao olhar o dado, estava certo.
- **Iterar e mutar o mesmo dicionário** é seguro em Swift por causa da cópia, mas em outras linguagens (Java, Python) é erro em tempo de execução. Não generalize.
- **Para a 5b**: `atualizar(categorias:)` precisa reindexar os livros afetados, porque os nomes das categorias entram no índice.

### Para ir além
- Manning, Raghavan e Schütze, *Introduction to Information Retrieval*, cap. 3 (dicionários e consultas por prefixo/curingas) e cap. 6 (ranking); nlp.stanford.edu/IR-book.
- Transformada de Schwartz (decorate-sort-undecorate): o nome vem de Randal Schwartz, que popularizou o padrão em Perl nos anos 1990; o verbete "Schwartzian transform" da Wikipédia resume a ideia e o custo.
- *The Swift Programming Language*, capítulo "Structures and Classes" (tipos-valor e copy-on-write) e a documentação de `Dictionary` e `Set.remove`.

### Perguntas
1. Com suas palavras: por que o motor guarda `[UUID: Livro]` além do índice, e por que o filtro roda depois do BM25F? O que mudaria na nota de um livro se rodasse antes?
2. Aplicação: o produto decide que, quando o E devolver lista vazia, a busca deve tentar OU. Onde em `buscar` você mexeria, o que precisa mudar na ordenação (as notas dos dois grupos são comparáveis?) e como o teste "prev prev" se comportaria?
3. Raciocínio: a biblioteca tem "Prisão preventiva" e "Prevenção do crime", e o usuário digita "prevent" (última palavra), depois "preven". Quais livros voltam em cada caso e por quê? Dica: pense em quais termos do vocabulário começam com cada prefixo e no que a regra "maior nota entre as expansões" faz.

### Minhas respostas
(sem respostas)

## Tarefa 2.3f — Item do sumário e categorias no motor (passo 5b) (2026-10-09)

### O que foi feito
`ResultadoBusca` ganhou `itemDoSumario: ItemSumario?`, e `MotorDeBusca` ganhou `melhorItem` (escolhe o item do sumário que mais casa com a consulta) e `atualizar(categorias:)` (reindexa só os livros afetados por renomear, apagar ou criar categorias). As expansões do prefixo agora são calculadas uma vez em `buscar`. Testes em `MotorDeBuscaTests.swift`; suíte em 144 testes, 0 falhas, Xcode 14.2. Com isso o passo 5 da 2.3 está fechado; falta o passo 6 (consultas de referência e ajuste dos pesos).

### Conceitos envolvidos

#### 1. Resultado em dois níveis: livro e item
A tela mostra "Livro · item do sumário, p. N · Estante X · prateleira". Cada pedaço vem de um lugar diferente:
```mermaid
flowchart LR
  R[ResultadoBusca] --> L[livro]
  R --> I["itemDoSumario (página)"]
  L --> P[prateleira]
  L --> E["estanteId, resolvido pela tela"]
```
A página mora no item, a prateleira no livro, e o nome da estante é resolvido pela tela a partir de `estanteId`. Guardar o nome no resultado obrigaria a reindexar ao renomear uma estante.

#### 2. Escolher o melhor item: mesma regra do livro
`melhorItem` percorre `indice.itensSumario(doLivro:)` e dá a cada item uma nota com a mesma regra usada no livro: soma dos termos fixos mais a maior nota entre as expansões do prefixo do último termo. Guardar o máximo corrente é uma varredura O(n) sobre os itens. Detalhes que importam:
- Parte-se de 0 e compara-se com `>`. Item sem nenhum termo tem nota 0 e nunca vence; se nenhum vence, o resultado é `nil` (o livro casou pelo título ou autor).
- `>` e não `>=`: no empate fica o primeiro do sumário. O teste de empate pegaria a troca por `>=`, porque com `>=` ficaria o último.
- Só é calculado para os livros que passaram no filtro; quem sai não gasta cálculo.
- Listagem só por filtro (consulta vazia) devolve `nil`: não há termos para casar.

#### 3. Inverter quem dirige o laço (o ganho de desempenho)
Primeira versão: para cada expansão, para cada item, `notaDoItem`. Com o prefixo "pr" há centenas de expansões; multiplicadas por itens e por livros, a cada tecla digitada. Versão final: cria-se um `Set(expansoes)` uma vez por consulta e percorrem-se os termos **do item** (`item.frequencias.keys.filter(expansoes.contains)`).
- Antes: custo O(expansões) por item.
- Depois: O(tamanho do item), com cada consulta ao Set em O(1) esperado (tabela hash).

Regra geral: itere o conjunto pequeno e consulte o grande numa estrutura de busca O(1). Quem é "pequeno" aqui é o item (poucos termos), não o vocabulário expandido.

#### 4. Reindexar quando um dado derivado muda
O índice grava os **nomes** das categorias (decisão da 2.3b), não os ids. O nome é um dado derivado copiado para dentro do índice; se muda na fonte, a cópia fica velha. É o problema clássico de invalidação de cache/desnormalização: ou se reindexa quem foi afetado, ou se aceita resultado desatualizado. Aqui reindexa-se, e só os afetados.

A expressão central:
```swift
let afetadas = Set(antigos.keys).union(novos.keys).filter { antigos[$0] != novos[$0] }
```
`antigos[$0]` e `novos[$0]` são `String?`. Comparar opcionais cobre três casos numa única condição:
| Caso | antigo | novo | diferem? |
| --- | --- | --- | --- |
| renomeada | "A" | "B" | sim |
| apagada | "A" | nil | sim |
| nova | nil | "B" | sim |
| inalterada | "A" | "A" | não |

A "nova" conta porque um livro pode ter recebido o id da categoria antes de o motor conhecer seu nome (o índice teria gravado o livro sem aquele nome).

Das apagadas, o livro também **perde o id** (`livro.categoriaIds.subtract(apagadas)`). Isso espelha o `nullify` do Core Data (apagar a categoria remove a relação nos livros). Sem isso, o filtro por categoria ainda acharia o id antigo, que já não existe.

Ordem importa: `nomesDasCategorias = novos` é trocado **antes** do laço, porque `atualizar(livro)` consulta esse dicionário para montar o texto indexado e precisa dos nomes novos.

Iterar `livros.values` enquanto `atualizar` altera `livros` é seguro: `values` é copiada por valor (copy-on-write), como no laço do E na 2.3e. O `guard !afetadas.isEmpty` evita a varredura quando nada mudou. Complexidade: O(C) para comparar categorias, mais O(L) para varrer os livros, mais o custo de reindexar cada afetado.

### Por que assim
Decisões aprovadas, numeradas:
1. **`itemDoSumario: ItemSumario?` no resultado.** Página vem do item, prateleira do livro, nome da estante resolvido pela tela (renomear estante não reindexa).
2. **Item mostrado = maior `BM25.notaDoItem`** pela mesma regra do livro; empate vai para o primeiro do sumário (`>`, não `>=`); nenhum item com os termos dá `nil`; só para livros que passaram no filtro; consulta vazia dá `nil`. O item é localizado por **id** no livro. A revisão sugeriu guardar a posição; ficou o id, porque é correto mesmo se a ordem do índice divergir da do livro, e a busca linear num sumário é barata.
3. **`atualizar(categorias:)`** reindexa só os livros afetados (união de ids antigos e novos cujo nome difere), tira dos livros os ids apagados, troca `nomesDasCategorias` antes do laço. Ids que o motor nunca conheceu (nem antes nem agora) ficam no livro; está documentado.
4. **Refatoração:** as expansões do prefixo são calculadas uma vez em `buscar` e passadas a `notasDoUltimo` e `melhorItem`. A regra de "repetido não expande" e do mínimo de 2 letras fica num lugar só.

Revisão (Ricardo aprovou 1, 2, 4, 5, 6; recusou 3 e 7):
1. Aplicado (desempenho): `Set(expansoes)` e laço pelos termos do item (ver conceito 3).
2. Aplicado: comentário explicando que partir de 0 com `>` é o que gera `nil` quando nenhum item tem os termos.
4. Aplicado: documentação dos ids órfãos.
5. Aplicado: testes novos.
   - "prisao temporar": termo fixo mais prefixo juntos; só o item com os dois vence.
   - "pena": expansões "penal" (primeira alfabeticamente, presente nos 3 livros, IDF baixo, cerca de 0,13) e "penas" (só num item, IDF cerca de 0,98). Vence "Aplicação das penas". O teste falharia se o código usasse só a primeira expansão.
6. Aplicado: livro com duas categorias e uma apagada (só aquele id sai, a outra continua buscável); `atualizar(categorias:)` com a mesma lista não muda o resultado.
3 e 7, recusados: ver abaixo.

### Alternativas descartadas
- **Guardar a posição do item em vez do id** (achado 3, recusado): a posição seria mais rápida, mas quebra em silêncio se a ordem do índice e a do livro divergirem. Com sumários de dezenas de itens, a busca linear é irrelevante.
- **Renomear `atualizar(categorias:)` para `trocarCategorias`** (achado 7, recusado): o nome segue o padrão `atualizar(_ livro:)` e a documentação explica o efeito.
- **Reindexar todos os livros a cada mudança de categoria:** correto, mas O(L) reindexações; renomear uma categoria é raro, mas desnecessariamente caro.
- **Guardar ids de categoria no índice, resolvendo nomes na consulta:** evitaria reindexar, mas o BM25F precisa do texto dos nomes para ponderar o campo; foi decisão da 2.3b.
- **Nome da estante no resultado:** obrigaria reindexar ao renomear estante.

### Padrões e boas práticas
- **Inverter o laço / usar Set como índice de pertinência:** quando um lado é pequeno e o outro grande, itere o pequeno. Não vale a pena se ambos forem pequenos; legibilidade vence.
- **Calcular uma vez por consulta, usar muitas vezes:** o mesmo princípio do `Preparado` (2.3e).
- **Invalidar só o que mudou:** reindexação incremental. Não use quando a mudança é rara e a lista pequena: o ganho some e o código fica mais difícil de provar correto.
- **Fonte única de regra:** "como pontuar um termo" vale para livro e item.
- **Teste que distingue o certo do errado:** o teste do "penal/penas" falha se a implementação usar só a primeira expansão; o de empate falha se trocar `>` por `>=`.

### Armadilhas
- **`>=` no lugar de `>`:** o último item empatado vence e o resultado muda sem erro de compilação. Só um teste de empate pega.
- **Nota inicial 0 com item de nota 0:** sem a comparação estrita partindo de 0, um item sem nenhum termo viraria "melhor".
- **Trocar `nomesDasCategorias` depois do laço:** reindexaria com os nomes velhos e o bug só apareceria na busca por nome de categoria.
- **Comparar só ids antigos e novos** (sem comparar nomes) perde renomeações; comparar só nomes perde categorias novas com ids que livros já referenciam.
- **Esquecer de retirar os ids apagados do livro:** o filtro por categoria devolve livro de categoria que não existe.

### Para ir além
- Manning, Raghavan e Schütze, *Introduction to Information Retrieval*, cap. 4 e 5 (construção e atualização de índices).
- Documentação do Swift sobre `Set` e `Dictionary` (complexidade de `contains` e subscript) e sobre comparação de `Optional` (`Equatable`).
- Martin Kleppmann, *Designing Data-Intensive Applications*, cap. 3 (índices) e 11 (dados derivados e manutenção de visões).

### Perguntas
1. Com suas palavras: por que `melhorItem` só é chamado para os livros que passaram no filtro, e por que `atualizar(categorias:)` troca `nomesDasCategorias` antes do laço de reindexação? O que quebraria em cada caso se a ordem fosse inversa?
2. Aplicação: o usuário digita "pr". Explique quantas chamadas a `notaDoItem` a primeira versão fazia (em termos de E expansões, I itens, L livros) e quantas faz a versão final. E se o sumário de cada livro tivesse 2.000 itens com 200 termos cada, a mudança ainda valeria a pena? Justifique.
3. Raciocínio: a categoria "Penal" (id X) é renomeada para "Direito penal", e outra categoria "Civil" (id Y) é apagada. Em `atualizar(categorias:)`, quais ids entram em `afetadas`, quais em `apagadas`, e o que acontece com um livro que tinha X e Y? E o que acontece se a nova lista trouxer uma categoria Z que nenhum livro conhecido referencia?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

(sem respostas)

## Tarefa 2.3g — Planejamento a partir das fotos reais: o plano muda (2026-10-09)

### O que foi feito
Sem código. Depois de fotografar 4 livros reais, `docs/PLANO.md` e `CLAUDE.md` foram atualizados: nova ordem de confiança das fontes de identificação, três parsers sobre uma struct `LinhaOCR`, modelo de `Livro` ampliado para obras em vários volumes (nova tarefa 2.3b, antes do passo 6 da busca), `pagina` como texto, hífen no tokenizador e `numeracao`/`parte` indexados. Fotos ficam fora do Git; o OCR é gravado em JSON e commitado.

### Conceitos envolvidos

**1. Validar o plano contra dados reais.** O plano de 03/10 supunha ISBN e ficha CIP na maioria dos livros. As fotos mostraram o contrário: nenhum dos 4 tem ISBN (o ISBN só existe desde ~1970 e se generalizou depois), 3 são de 1954–1972 e só têm folha de rosto. Quatro livros não são estatística, mas bastam para derrubar uma suposição. Por isso o plano passou a medir acerto num conjunto de avaliação em vez de confiar na intuição.

**2. Ordem de confiança.** Cada fonte tem uma taxa de erro diferente: código de barras (determinístico, dígito verificador) > ficha CIP (formato padronizado, ISBD) > folha de rosto (layout livre, mas semântico) > capa (decorativa) > Gemini (generativo, pode alucinar) > manual (sempre disponível). A ordem vai do mais verificável ao menos verificável; o Gemini fica depois dos algoritmos porque seu erro é silencioso.

**3. `LinhaOCR` e a porta do Domínio.** O Vision devolve `VNRecognizedTextObservation` com `boundingBox` (CGRect normalizado 0–1, origem no canto inferior esquerdo). O Domínio só importa Foundation, então ele define sua própria struct:

```swift
struct LinhaOCR { let texto: String; let x, y, largura, altura: Double; let confianca: Double }
```

`Dados/Visao` converte Vision para `LinhaOCR`. Isso é a mesma inversão de dependência do resto do projeto: a regra (parser) não conhece o detalhe (framework). Benefício concreto: o parser vira função pura `[LinhaOCR] -> Resultado`, testável com JSON gravado, inclusive na CI sem Vision nem fotos. Cuidado com o eixo y: no Vision, y=0 é a base da página; se o Domínio adotar "y cresce para baixo", a conversão tem de acontecer em um só lugar (a fronteira) e estar documentada.

**4. Geometria como sinal.** OCR puro devolve linhas de texto sem hierarquia. Mas a altura da caixa aproxima o tamanho da fonte, e na folha de rosto o tamanho da fonte diz o papel: maiores linhas = título; médias = subtítulo/parte; pequenas no rodapé = editora, local, ano. No sumário, a geometria resolve outro problema: uma entrada pode ocupar várias linhas e o número da página nem sempre está na última. A regra "a página é o número da coluna da direita (x > ~85%) cujo y cai dentro do bloco da entrada" substitui "número no fim da linha". Isso é uma troca de unidade de análise: da linha para o bloco (entrada), definido por âncoras ("§ 5.108.", "Art. 1.710 —", "1.", "I"). Fica mais robusto, mas depende de calibrar limiares (85%, tolerância de y) com dados; daí o conjunto de avaliação.

**5. `rotulo` × `numeracao` (a discussão com o Ricardo).** Semanticamente diferem: "Capítulo II" ou "1.2.3" é posição estrutural no livro; "Art. 1.710" ou "§ 5.108" é referência externa (a lei), que é o que o advogado procura. Mas cada item impresso tem um único prefixo, então um campo não perde dado. A diferença real é de busca: antes, `numeracao` não era indexada (só o título do item). Opções:

| | Um campo indexado | Dois campos |
| --- | --- | --- |
| Ruído | pequeno: "1.2.3" vira o termo `123` | nenhum (só a âncora jurídica indexada) |
| Tipo explícito | não | sim |
| Custo | zero | campo extra em tela, Core Data, export, validação |

Escolhido um campo. Regra geral: não modele distinções que nenhum comportamento usa (YAGNI); se algum dia a interface precisar tratá-las diferente, separar é uma migração localizada.

**6. Página como `String?` e sequências.** Prefácios usam romanos ("XII"); o corpo, arábicos. `Int?` perde os romanos; só `String` perde a ordem (e o aviso "página menor que a anterior"). Solução: guardar o texto impresso e ter uma regra pura que converte romano/arábico em número. A `ValidacaoSumario` compara só dentro da mesma sequência: "XII" → "1" é troca de sequência, não regressão. Romano -> inteiro: percorre os símbolos somando; se um símbolo é menor que o seguinte, subtrai (IV = 5 - 1). É O(n) no tamanho da string. Descartado `Int` + flag `ehRomano`: não representa "XI-XII" nem "245-246".

**7. Tokenizador e o hífen.** Duas situações com o mesmo caractere:
- entre letras ("sub-rogação"): remover, juntando em `subrogacao`, para casar com quem digita sem hífen;
- entre dígitos ("1.710-1.779"): continua separando. Se fosse removido, o intervalo viraria um termo só (`17101779`) e "art 1710" nunca o acharia.

A proposta original ("remover hífens") teria introduzido esse bug. Já "art. 1.710" → `art 1710` funcionava porque o ponto entre dígitos some; e a ortografia antiga ("sôbre", "emprêsa") já casa com a atual porque o Tokenizador remove acentos (normalização Unicode NFD e descarte de marcas combinantes). A lição: antes de adicionar regra, testar o que a regra existente já faz.

**8. Mudar o esquema antes de haver dados.** Core Data exige migração (leve ou mapeada) quando o modelo muda com dados gravados. Como ainda não há dados em aparelho e o export v1 (2.8) não existe, editar o `.xcdatamodeld` direto é de graça; depois da 2.4 e do export, cada campo novo custaria migração e versão do JSON. Daí a ordem: 2.3b antes de tudo isso. Pela mesma lógica, a 2.3b vem antes do passo 6: o conjunto de consultas de referência precisa incluir "art 1710", parte e hífens, senão os pesos do BM25F seriam ajustados duas vezes.

**9. Dados de teste com direitos autorais.** Fotos de livros ficam fora do Git (direitos e tamanho de binários, que o Git guarda para sempre). O que se versiona é o OCR em JSON (texto, caixa, confiança) e o gabarito. É o padrão "golden files": entrada gravada, saída esperada anotada à mão. Limite: o JSON não testa o Vision em si, apenas os parsers; mudanças no OCR da Apple (iOS 16 no Xcode 14 × iOS 26 na CI) não aparecem aí, e isso é aceitável porque o JSON é determinístico.

### Por que assim
- Ordem de confiança refinada, não revertida: a decisão de 03/10 (algoritmo antes de IA) continua valendo; o "algoritmo" apenas virou três fontes.
- Parsers sobre `LinhaOCR`: testáveis e independentes do Vision.
- Modelo ampliado agora: custo de mudança mínimo hoje, alto depois.
- CDD e assuntos da ficha CIP fora do `Livro`: mantém a decisão de 03/10 (categorias no lugar de assuntos); os assuntos viram sugestão de categorias na confirmação.
- LexML: volume/edição/ano entram na pontuação como desempate de títulos iguais, mas só depois de conferir como o LexML registra volumes (pode ser no título ou um registro por tomo). Planejar sem verificar seria chute.

### Alternativas descartadas
- Dois campos `rotulo` e `numeracao`: ver conceito 5.
- `pagina` só `String` ou `Int` + flag: ver conceito 6.
- Fotos como recursos do alvo de testes (ideia anterior): pesadas, com direitos autorais, e obrigariam rodar Vision na CI.
- Remover todos os hífens: ver conceito 7.
- Parser por linha para o sumário: falha com entradas de várias linhas e página fora da última.
- Migrar o Core Data depois: custo evitável.

### Padrões e boas práticas
- Inversão de dependência na fronteira (`LinhaOCR`): use quando a regra é valiosa e o framework volátil; não vale para um detalhe de uso único.
- Golden files / gabarito: bom para parsers heurísticos; ruim se o gabarito for tão grande que ninguém o mantém.
- Decidir com métrica (acerto por campo) em vez de opinião.
- YAGNI no modelo de dados: só crie campos que mudam algum comportamento.
- Registrar a decisão com o motivo (tabela do PLANO), inclusive o que foi refinado e não revertido.

### Armadilhas
- Eixo y do Vision (origem embaixo) versus a lógica "topo da página" dos parsers: bug clássico que inverte título e rodapé.
- Limiares geométricos (85%, tolerâncias) calibrados em 4 livros: podem não generalizar; por isso ampliar para ~30.
- Foto com a página curva ou com transparência do verso: o OCR gera lixo; filtrar por confiança.
- Romano ambíguo: "MIX" ou "CIVIL" parecem romanos; só aplique a conversão em campos onde romano é esperado (volume, página).
- `edicao` guardando reimpressão: ao comparar edições, "3.ª ed., 2.ª reimpr." não é igual a "3.ª ed."; o gabarito separa para medir, o app junta.
- Indexar `numeracao` aumenta o índice com termos como `123`: ruído aceito, mas observe no passo 6.

### Para ir além
- Documentação Apple: `VNRecognizedTextObservation` e `VNRectangleObservation.boundingBox` (sistema de coordenadas normalizado).
- Manning, Raghavan e Schütze, *Introduction to Information Retrieval*, cap. 2 (tokenização e normalização).
- Documentação Apple, "Core Data Model Versioning and Data Migration".

### Perguntas
1. Com suas palavras: por que `LinhaOCR` é definida no Domínio em vez de usar `VNRecognizedTextObservation` direto no parser? O que se ganha nos testes?
2. Aplicação: o hífen entre letras é removido e entre dígitos separa. Como o `Tokenizador` trataria "sub-rogação nos arts. 1.710-1.779" e quais termos sairiam? E por que "remover todos os hífens" quebraria a busca por "art 1710"?
3. Raciocínio: um tomo tem as páginas "XI", "XII", "1", "2", ... "245". Descreva como a `ValidacaoSumario` por sequência trataria cada transição e o que aconteceria com `Int?` simples. Depois diga quando separar `rotulo` e `numeracao` em dois campos passaria a valer a pena.

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

(sem respostas)

---

## Tarefa 2.3b — Obras em vários volumes: modelo, página como texto, numeração/parte no índice e hífen (2026-10-09)

### O que foi feito
O modelo e a busca foram ajustados aos achados das fotos reais (tomos, páginas em romanos, âncoras como "Art. 1.710"), em cinco passos com um commit cada. Nasceu `Dominio/Regras/NumeroDePagina.swift`; `ItemSumario.pagina` virou `String?` e a `ValidacaoSumario` passou a comparar páginas por sequência; o `Livro` ganhou `local`, `volume`, `volumeRotulo`, `parte`, `serie`, `artigosInicio`/`artigosFim` (com Core Data e `Conversao.swift`); o `IndiceInvertido` passou a indexar `numeracao` e `parte`; o `Tokenizador` passou a juntar hífen entre letras. Testes: 144 → 171, todos verdes no Xcode 14.2.

### Conceitos envolvidos

**1. Ordem das mudanças: dependências, não gosto.** A sequência foi regra pura → tipo do Domínio que a usa → persistência → índice, e o hífen por último (mexe na busca, como o índice). Cada commit compila e passa nos testes; isso permite `git bisect` útil se algo quebrar depois. Trocar o tipo de `pagina` no Domínio quebra a compilação de `Conversao.swift`, por isso Domínio e Core Data entraram no mesmo commit: o critério é "cada commit deixa o projeto verde", não "uma camada por commit".

**2. Enum com valor associado como modelo de "sequência + número".**

```swift
enum NumeroDePagina: Equatable { case arabico(Int), romano(Int) }
```

O *caso* diz a sequência; o valor diz a posição nela. Compare com `Int` + `Bool ehRomano`: o enum não admite estados incoerentes e o compilador obriga a tratar os dois casos num `switch`. Na `ValidacaoSumario`, o padrão `case let (.arabico(a), .arabico(b)), let (.romano(a), .romano(b))` casa a tupla `(anterior, atual)` só quando as sequências são iguais; qualquer outra combinação cai no `default` (troca de sequência, sem aviso).

**3. Romano estrito: soma + ida e volta.**
- Conversão romano → inteiro, O(n): percorre da esquerda para a direita; se o símbolo é menor que o seguinte, subtrai (IV = −1 + 5), senão soma. "XLVIII" = −10 + 50 + 5 + 1 + 1 + 1 = 48.
- Só isso aceitaria lixo: "IIIII" daria 5, "IC" daria 99, "VX" daria 5. Em vez de uma lista de regras ("I só antes de V e X", "V nunca se repete"...), converte-se o total de volta para o romano canônico e compara-se com a entrada: se não for idêntica, não era um romano válido.
- A volta é um algoritmo guloso sobre a tabela ordenada `M, CM, D, CD, C, XC, L, XL, X, IX, V, IV, I`: enquanto o resto comporta o maior valor, anota o símbolo e subtrai. Funciona porque a tabela inclui os pares subtrativos como "moedas" próprias (é o problema do troco com um sistema de moedas em que o guloso é ótimo). Faixa 1–3999, o que sete símbolos representam.
- Vale como propriedade: o teste converte de 1 a 3999 e volta, e exige igualdade (teste "de ida e volta" é uma forma barata de teste de propriedade).
- Ao contrário de uma regex de romanos (correta, mas ilegível), a verificação reaproveita a função de conversão que já era necessária.

**4. Página como texto e valor derivado.** O dado persistido é o que está impresso ("XI", "245–246", "s/n"). O número é calculado (`numeroDaPagina`), não guardado. Dois campos com a mesma informação podem divergir (alguém muda um e esquece o outro); derivar custa O(tamanho do texto), irrelevante. Regra geral: guarde a fonte da verdade, derive o resto, a menos que a derivação seja cara.

**5. Comparar com o item anterior imediato.** A `ValidacaoSumario` compara cada página com a do item anterior que tenha página interpretável, e só avisa se for da mesma sequência e maior. "s/n" é pulado (nem avisa nem interrompe). Exemplo: `20, s/n, 10` avisa no índice 2, porque o "s/n" não conta. Alternativa descartada: comparar com o último item *da mesma sequência*. Num índice remissivo em romanos no fim do livro ("I"), isso avisaria contra o "XII" do prefácio, um falso alarme. Falso positivo em validação é pior do que parece: o usuário aprende a ignorar os avisos.

**6. Modelo plano.** Campos novos do `Livro`: `local`, `volume: Int?` (número, para ordenar tomos e desempatar no LexML), `volumeRotulo` (o texto impresso que a tela mostra), `parte` (texto médio da folha de rosto), `serie` (da ficha CIP), `artigosInicio`/`artigosFim`. Todos opcionais, com padrão `nil` no `init`: por isso as chamadas existentes não mudaram (parâmetros com valor padrão são a forma de evoluir um `init` sem quebrar quem o usa). `volume` e `volumeRotulo` parecem redundantes, mas têm papéis distintos: um é para a máquina ordenar, outro para a pessoa ler ("Tomo XLVIII"). No Core Data, `Int?` vira `Integer 32` com `NSNumber?`; é por isso que o repositório testa que o livro mínimo volta com `nil` e não `0` ou `""`: o Core Data confunde fácil "ausente" e "zero".

**7. Sem migração, mas com uma armadilha.** Como não há dados gravados, o `.xcdatamodel` foi editado direto, sem criar versão de modelo. Quem já rodou o app no simulador tem um banco com `pagina` Integer; o Core Data não abre esse arquivo com o modelo novo (falha ao carregar a store). Solução: apagar o app do simulador. Os testes usam store em memória e não sofrem. Isso só é aceitável antes da 2.4 e do export v1; depois, cada mudança custaria migração.

**8. O que entra em qual campo do índice.** O índice invertido guarda, por campo, a frequência de cada termo. Agora, os termos de cada item do sumário são `termos(numeracao) + termos(titulo)`, tanto no campo `sumario` do livro quanto nas frequências de cada `ItemSumarioIndexado` (de onde o motor tira o item mostrado no resultado). Assim, "art 1710" acha o livro e destaca o item "Art. 1.710" (e não o "Art. 1.709", que não tem o termo `1710`). A `parte` entra no campo `subtitulo`, com o mesmo peso: tem o papel de um subtítulo. O custo é ruído: "1.2.3" vira o termo `123`, aceito.

**9. Hífen no tokenizador.** A regra: hífen entre duas letras é pulado, como o ponto entre dígitos. "sub-rogação" → `subrogacao`, igual a quem digita "subrogacao". Em qualquer outra posição continua separando: "1.710-1.779" → `1710`, `1779`; "CPC-2015" → `cpc`, `2015`. Detalhes:
- Contam como hífen U+002D, U+2010 e U+2011 (o PDF/OCR traz variantes). O travessão (–, —) é pontuação entre palavras e continua separando.
- O hífen invisível U+00AD (*soft hyphen*) sempre some: é uma marca de onde quebrar a linha, que vem junto em texto copiado.
- O ponto e o hífen compartilham uma função `entre(caracteres, i, teste)`, chamada com `isNumber` ou `isLetter`: duas regras quase iguais viraram uma regra parametrizada pelo predicado.
- Como índice e consulta passam pelo mesmo tokenizador, "sub-rogação", "subrogação" e "sub-rogacao" produzem o mesmo termo. Essa simetria é o que torna qualquer normalização segura.

### Por que assim
- Mudar o modelo agora, antes das telas (2.4) e do export (2.8): é o momento de custo mínimo.
- Antes do passo 6: o conjunto de consultas de referência precisa conter "art 1710", parte e hífens, senão os pesos do BM25F seriam ajustados duas vezes.
- Derivar `numeroDaPagina` em vez de guardar: ver conceito 4.
- `parte` no campo `subtitulo` e `numeracao` no `sumario`: reaproveita os pesos existentes. Um `CampoBusca.parte` novo seria mais um parâmetro a calibrar no passo 6 sem comportamento diferente.
- Sem validar `artigosInicio ≤ artigosFim` ainda: nenhuma tela grava esses campos antes da 2.4 (YAGNI); a validação nasce junto com quem os grava.

### Alternativas descartadas
- `pagina: Int?`: perde romanos. `Int` + flag `ehRomano`: não representa "XI-XII" e exigiria dois atributos no Core Data e no export.
- Soma de romanos sem conferência: aceita "IIIII". Regex de romanos: correta, porém ilegível; a ida e volta reaproveita código.
- Struct `Volume` aninhada no `Livro`: Core Data e JSON são planos, a conversão ganharia um nível sem ganho de comportamento.
- Indexar `volumeRotulo` e `serie`: fica para o passo 6 se alguma consulta de referência pedir.
- Remover todos os hífens: criaria `17101779` e "art 1710" não acharia o intervalo.
- Indexar as duas formas (`sub`, `rogacao` e `subrogacao`): o BM25F contaria o conceito duas vezes e inflaria o comprimento do campo, distorcendo a normalização por comprimento.

### Padrões e boas práticas
- Tipos que tornam estados inválidos irrepresentáveis (enum com valor associado). Não vale quando as variantes não mudam o comportamento.
- Fonte da verdade + valor derivado (conceito 4).
- Teste como especificação: o teste antigo `testHifenETravessaoSeparam` ("Pós-graduação" → `pos`, `graduacao`) descrevia a regra anterior. Foi reescrito para `posgraduacao`, porque a decisão mudou. Se um teste antigo falha depois de uma decisão deliberada, o certo é atualizar a especificação, mas só depois de ter certeza de que a decisão é intencional (aqui, estava na explicação aprovada).
- Teste de ida e volta (round trip) para conversões e para persistência (tomo completo no repositório).
- Commits que compilam individualmente.

### Armadilhas
- Banco antigo no simulador não abre depois de mudar o tipo de um atributo: apague o app do simulador (sintoma: erro ao carregar a persistent store, ou crash na inicialização).
- `NSNumber?` no Core Data: `0` e ausente são coisas diferentes; teste o `nil`.
- Romano ambíguo: "MIX" e "CIVIL" parecem romanos; só interprete como romano em campos onde ele é esperado (página, volume).
- Limite aceito do hífen: "sub rogação" (com espaço) não casa com "sub-rogação"; e a quebra de linha com hífen do OCR ("sub-\nrogação") é problema do parser, na Fase 3, pois o tokenizador vê o caractere de nova linha e separa.
- O intervalo de página "245–246" usa travessão; por isso `interpretar` trata hífens e travessões como separadores de intervalo (e o tokenizador, não).
- Comparar sempre com o último item: um "s/n" no meio não pode quebrar a cadeia de comparação.

### Para ir além
- Manning, Raghavan e Schütze, *Introduction to Information Retrieval*, cap. 2 (tokenização e normalização; o trecho sobre hífens discute exatamente esse dilema).
- Documentação Apple, "Core Data Model Versioning and Data Migration" (o que seria necessário se já houvesse dados).
- *The Swift Programming Language*, capítulo "Enumerations" (valores associados) e "Patterns" (padrões em tuplas e `case let`).

### Perguntas
1. Com suas palavras: por que `NumeroDePagina.interpretar("IIIII")` devolve `nil`, se a soma dos símbolos dá 5? Descreva a conferência de ida e volta.
2. Aplicação: o advogado quer buscar "arts 1710 1779" e achar o tomo cujos artigos vão de 1.710 a 1.779. Que termos o tokenizador gera para "Arts. 1.710-1.779" e por que a busca funciona? O que mudaria se o hífen entre dígitos fosse removido?
3. Raciocínio: um sumário tem as páginas "XI", "XII", "s/n", "1", "2", "XIV". Quais avisos a `ValidacaoSumario` emite, e em que índice? Depois diga por que comparar com "o último item da mesma sequência" geraria um falso alarme num índice remissivo em romanos no fim do livro.

### Minhas respostas
(sem respostas)

## Tarefa 2.3h — Consultas de referência e ajuste dos pesos do BM25F (passo 6 da 2.3) (2026-10-09)

### O que foi feito
Foram criadas as métricas de qualidade da busca (`MetricasDeBusca.swift`, no alvo de testes), uma biblioteca de 22 fichas de livros (`BibliotecaDeReferencia.swift`) com 25 consultas (`ConsultasDeReferencia.swift`: 19 de ajuste e 6 sondas) e um relatório `[referencia]` que o `scripts/testar.sh` deixa no log. Depois, uma varredura de parâmetros (`testVarreduraDosParametros`) mostrou que só o peso e o `b` do sumário mudam algum resultado. O padrão do peso do sumário passou de 1,0 para 0,5 em `ParametrosBM25F.padrao` (`BM25F.swift`), e um teste de piso (`testMetricasNaoCaemAbaixoDoPiso`) impede regressões. A suíte foi de 171 para 185 testes.

### Conceitos envolvidos

**1. Por que medir a busca.** Até aqui os pesos do BM25F (título 3, sumário 1 etc.) eram palpites razoáveis. Ajustar um parâmetro "a olho" é perigoso: melhora uma consulta e piora outra sem que ninguém perceba. A solução da recuperação de informação é o *conjunto de avaliação*: consultas com a resposta certa conhecida, e métricas que resumem o ranking em um número. Mudar um parâmetro vira um experimento: o número subiu ou desceu? (Manning et al., cap. 8, descrevem o mesmo método, com o corpus de Cranfield como ancestral.)

**2. As métricas.** Seja p a posição do livro esperado no ranking.

| Métrica | Definição | O que mede | O que não vê |
| --- | --- | --- | --- |
| top 1 | fração das consultas com p = 1 | o "acerto de primeira" | 2º e 10º valem igual (zero) |
| top 3 | fração com p ≤ 3 | o livro está na tela sem rolar | diferença entre 1º e 3º |
| MRR | média de 1/p (0 se ausente) | qualidade média do ranking | quase tudo é dominado pelas primeiras posições |
| item certo | entre as consultas que esperam um item do sumário e acharam o livro no top 3, fração com o item mostrado certo | o destaque "página 245, § 5.153" | consultas sem item esperado |

O MRR (*mean reciprocal rank*) existe porque top 1 é cego a quase-acertos. 1/p vale 1; 0,5; 0,333; ...; 0,1 para o 10º. Assim ele separa o 2º do 10º, o que o top 1 e o top 3 não fazem. O custo: o MRR é uma média de frações, então a diferença entre p=2 e p=3 (0,5 → 0,333) pesa mais do que a entre p=9 e p=10 (0,111 → 0,1). Isso é desejado: o usuário olha o topo.

Exemplo: 4 consultas com posições 1, 1, 2, 4 dão top 1 = 0,5; top 3 = 0,75; MRR = (1 + 1 + 0,5 + 0,25)/4 = 0,6875.

**3. Empate pessimista.** O motor desempata notas iguais por título e depois por UUID. Se a métrica usasse a posição que o motor devolve, um livro empatado com outro ganharia o 1º lugar só porque o título vem antes no alfabeto, ou seja, pontos por sorte, e uma mudança de nome mudaria a métrica. A regra adotada: p = 1 + (número de outros livros com nota ≥ a do esperado). Num empate a dois, o esperado fica em 2º, nunca em 1º. A comparação usa tolerância de 1e-9 porque ponto flutuante não é exato: em Double, `0.1 + 0.2 != 0.3` (dá 0.30000000000000004). Há um teste com exatamente esse par. Sem tolerância, dois livros "empatados" matematicamente pareceriam desempatados por um erro de arredondamento.

**4. Por que testar o código de teste.** `MetricasDeBusca` não está no app: o app nunca calcula MRR. Por isso mora em `EstantesTests/`. Mas uma métrica errada é pior que nenhuma métrica: todo o ajuste dos pesos se apoiaria nela, sem nenhum sinal de que algo está errado. Daí os 10 testes. Regra geral: o instrumento de medição precisa ser mais confiável do que aquilo que ele mede.

**5. Uma biblioteca de referência precisa de vizinhos parecidos.** Se cada consulta só tem um candidato plausível, qualquer peso acerta tudo e a métrica não distingue nada (o teste é "fácil demais"). Por isso os 18 livros do LexML foram escolhidos em grupos que se confundem (processo penal e prisão, constituição, trabalho, civil), e os 4 livros fotografados entram com os dados reais transcritos (Lassale, Carvalho Santos vol. XXIV, Pontes de Miranda T48 e T1). Fichas inventadas foram descartadas por duas razões: é circular (você escreve o livro que seu algoritmo acha) e os tamanhos de campo seriam irreais, e o `b` do BM25F normaliza justamente por tamanho.

**6. Regra anti-sobreajuste.** Sobreajuste (*overfitting*) é ajustar os parâmetros até as consultas de teste passarem, sem que isso signifique melhoria em consultas novas. Com 19 consultas, é muito fácil. As defesas adotadas: as consultas foram escritas antes de ver o ranking; consulta existente nunca é reescrita para passar; e uma regra de parada (ver "Por que assim").

**7. Ajuste × sonda.** Uma consulta de ajuste pode mudar de resultado com algum peso. Uma sonda é um caso que *nenhum* peso conserta; ela mostra uma limitação da arquitetura. Ficam fora do MRR: se entrassem, baixariam a média de um jeito que nenhum parâmetro corrige, e o número perderia a capacidade de sinalizar. As 6 sondas:

| # | Consulta | Resultado | Causa |
| --- | --- | --- | --- |
| 20 | "arts 1710 1779" | nenhum resultado | o E é estrito e os artigos do tomo não estão no índice |
| 21 | "tratado 48" | nenhum | o volume não está indexado |
| 22 | "tratado direito privado" | T48 2,236 × T1 2,232 | não empatou: "direito" está no subtítulo e no sumário do T48 |
| 23 | "prisoes cautelares" | nenhum | plural; falta stemming (RSLP) |
| 24 | "procesos penal" | nenhum | erro de digitação |
| 25 | "lassalle" | nenhum | a ficha CIP grafa "Lassale" |

**8. Linha de base e os dois erros.** Com os pesos antigos (sumário 1,0; `b` do sumário 0,75): top 1 = 0,895 (17/19), top 3 = 1,000, MRR = 0,939, item certo = 1,000 (5/5). Todos os casos da 2.3b ("art 1710", "§ 5.108", parte, hífen, "dissídios") já saíam em 1º com o item certo. Os dois erros:

- **#1 "processo penal"**: Badaró ficou em 2º (Rosa 2,075 × Badaró 2,052). O título exato do Badaró perde porque o Rosa ("Teoria dos jogos e processo penal") tem "processo penal" em 3 itens do sumário. Diagnóstico: problema de *peso* (o sumário vale demais perto do título).
- **#11 "prisao caut"**: Fernandes em 3º (Capez 3,444 · Maluf 3,310 · Fernandes 3,250). Caso *misto*: Maluf tem "prisão cautelar" em 3 itens (peso), mas Capez vence porque a expansão do prefixo `cautelares`, que só existe nele, tem IDF maior, e o livro fica com a MAIOR nota entre as expansões do prefixo (regra da 2.3e). Parte do problema é estrutural, não de peso.

**9. Descida por coordenadas e dependência do caminho.** A varredura (`testVarreduraDosParametros`) faz *coordinate descent*: um parâmetro por vez, variando numa grade e mantendo os outros fixos, repetindo por até 2 voltas, em 9 passos: peso do sumário, `b` do sumário, peso do subtítulo, das categorias, do `cddirCaminho`, dos autores, `k1`, `b` do título, `b` do subtítulo. O título fica fixo em 3 como âncora. Por quê: multiplicar todos os pesos por c equivale a dividir `k1` por c (a nota do BM25F depende de peso × frequência / (k1 + ...)), então peso e `k1` são redundantes na escala; sem uma âncora haveria infinitas soluções equivalentes.

O algoritmo só garante um ótimo *local*. Prova prática: com a grade do sumário começando em 0,5, a descida parou em (peso 0,5, `b` 0), com MRR 0,974 mas item certo 0,800; começando em 0,25 parou em (0,25, `b` 0,75), MRR 0,974 e item 1,000. O ponto de partida e a ordem das coordenadas mudam o destino. A superfície de erro tem vales; o `b` e o peso do sumário interagem (um muda o efeito do outro), e é exatamente isso que a descida por coordenadas trata mal.

**10. O furo do critério de otimização.** Com `b` do sumário = 0, a #11 subiu do 3º para o 2º, mas a #19 passou a mostrar o item errado: o título longo da "Parte VII … dissídios coletivos …" venceu "§ 5.153 Dissídios coletivos", porque `notaDoItem` usa o mesmo `b` do sumário (sem normalização por comprimento, itens longos deixam de ser penalizados). O critério "subir o MRR e depois o top 1" não via isso. Correção, aprovada pelo Ricardo: o *item certo* virou uma **restrição** (nenhuma troca que o piore é aceita). Foi registrado com transparência que essa regra nasceu *depois* de ver o resultado. Isso importa: regra criada após o fato é exatamente o tipo de ajuste que se deve declarar.

**11. "Não discriminado" não é "validado".** Subtítulo, categorias, CDDir, autor, `k1` e `b` do subtítulo: nenhuma consulta mudou em nenhum valor da grade. Isso não prova que os valores de partida estão certos. Prova que *este conjunto de consultas* não os distingue. Eles ficam como estão, rotulados "não discriminados". O único com evidência contrária foi o `b` do título: abaixo de 0,5 piora #1 e #11, o que confirma 0,5.

### Por que assim
Resultado dos candidatos:

| | peso sumário | b sumário | top 1 | MRR | item | #1 | #11 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| linha de base | 1,0 | 0,75 | 0,895 | 0,939 | 1,000 | 2º | 3º |
| **A (escolhido)** | **0,5** | **0,75** | 0,947 | 0,965 | 1,000 | 1º | 3º |
| B (descartado) | 0,25 | 0,75 | 0,947 | 0,974 | 1,000 | 1º | 2º |
| (b = 0, descartado) | 0,5 | 0 | 0,947 | 0,974 | 0,800 | 1º | 2º |

Grade do peso do sumário a partir da linha de base: 0,25 → MRR 0,974 (#1 e #11 sobem); 0,5 → 0,965 (#1 sobe); de 0,75 a 2,0 → 0,939 (nada muda).

- **Por que A e não B.** A conserta o caso de peso puro (#1). O ganho extra de B vem só da #11, que é um caso misto (parte do erro é a regra do IDF das expansões, não o peso). Além disso, 0,25 está na ponta da grade (o sumário passaria a valer 1/12 do título) e nenhuma consulta mede o risco inverso: um termo que só aparece no sumário de um livro perder para categoria ou CDDir de outro. Regra de parada: **não perseguir uma consulta com valor extremo**. Um parâmetro no limite da grade costuma indicar que o modelo está compensando outro problema.
- **Por que o código de varredura só imprime.** A varredura "recomenda" 0,25 no relatório, e continuará recomendando. A decisão é humana: um otimizador automático só enxerga o MRR; quem decide enxerga também o risco.
- **Por que Swift e não JSON** para a biblioteca: o `Livro` ainda muda até a 2.8; no Swift, mudar o modelo vira *erro de compilação* e não erro em execução; e não é preciso tornar o `Livro` `Codable` só por causa de testes. UUIDs fixos (`00000000-…-%012d`) porque o desempate do motor usa título e depois id: com UUIDs aleatórios a ordem em empates mudaria a cada execução e os testes ficariam instáveis.
- **Por que testes de exemplo à mão mudaram.** `testExemploPrisao` e `testExemploPrisaoFlagrante` (BM25FTests) passaram a usar `parametrosDoExemplo` com os valores do enunciado: testam a *fórmula*, não o valor calibrado. Os números esperados não foram mexidos. Se o teste usasse `.padrao`, toda calibração futura quebraria um teste que não tem relação com ela. `MotorDeBuscaTests` passou sem mudança.
- **Pisos como snapshot.** `testMetricasNaoCaemAbaixoDoPiso`: top 1 ≥ 0,94; top 3 ≥ 1,00; MRR ≥ 0,96; item certo = 1. Se cair: reverter, ou baixar o piso num commit explicado. A mensagem lista quem piorou em relação às posições gravadas. Verificado de verdade: com o peso antigo o teste reprova com "top 1 … pioraram: #1 "processo penal" 1º→2º". (Um teste que nunca falhou não foi provado.)

### Alternativas descartadas
- **Um assert por consulta** ("a #1 tem que ser 1º"): qualquer troca 1º↔2º entre consultas legítimas reprovaria, tornando o teste frágil e fazendo as pessoas o desligarem. O piso agregado tolera trocas que se compensam.
- **Só imprimir o relatório**: a regressão passaria silenciosa na CI.
- **Busca em grade completa** (todas as combinações dos 9 parâmetros): custo exponencial (com as grades usadas na varredura, 6 · 5⁴ · 4⁴ = 960 mil combinações, cada uma rodando as 25 consultas; a descida por coordenadas testou 42 por volta) e mais sobreajuste, pois testar muitas combinações contra 19 consultas quase sempre acha uma que "acerta tudo" por acaso.
- **Fichas inventadas**: ver conceito 5.
- **Escolher B pelo MRR mais alto**: ver "Por que assim".
- **Encadear `+` no T48**: o T48 usa `Array([[...], paragrafo(...), ...].joined())` em vez de uma cadeia longa de `+`, porque o verificador de tipos do Swift 5.7 (Xcode 14.2) estoura com "expression too complex to be solved in reasonable time" em expressões grandes com tipos inferidos. Construir com `joined()` dá ao compilador tipos explícitos para resolver.

### Padrões e boas práticas
- **Conjunto de avaliação + métricas antes de otimizar**: não se melhora o que não se mede. Não vale a pena quando não há alguém para decidir o que é "certo" (aqui o Ricardo e as fotos são a verdade).
- **Separar conjunto de ajuste e de sondas**: separa o que o parâmetro pode consertar do que exige mudar o algoritmo.
- **Restrição além do objetivo**: otimizar uma métrica sob uma restrição (item certo = 1) é mais seguro do que otimizar um escalar único. Cuidado: quanto mais restrições você inventa depois de ver os resultados, mais seu processo se parece com o sobreajuste que queria evitar. Declarar a ordem dos fatos mitiga isso.
- **Helpers de dados de teste** (`uuid`, `item`, `paragrafo`, `lexml`): constroem fichas com poucas linhas por livro. O dado fica legível e o ruído de construção, escondido.
- **Teste de snapshot com piso**: bom para propriedades agregadas que podem variar um pouco; ruim para saídas exatas que você quer congelar.
- Não vale aplicar isto sem sentido para um corpus de 22 livros: com tão poucos dados, a conclusão é "indícios", não "prova" (ver armadilhas).

### Armadilhas
- **Amostra pequena**: 19 consultas. Uma única consulta vale 1/19 ≈ 5,3 pontos de top 1. A diferença entre 0,947 e 0,895 é *uma* consulta. Não se conclua demais.
- **Parâmetro na ponta da grade**: sinal de que o ótimo pode estar além, ou de que você está compensando outro defeito.
- **Variar um parâmetro e ver "nada mudou"** não significa que ele é inútil: significa que nenhuma consulta o exercita. Cobrir isso exige novas consultas (escritas antes de ver o resultado).
- **Dependência do caminho** na descida por coordenadas: sempre rode a partir de mais de um ponto inicial e compare.
- **Empate e ponto flutuante**: comparar `Double` com `==` em métricas (ver conceito 3).
- **`descricao` do LexML cortada em 400 caracteres**: no Supabase, 10.145 dos 24.118 registros têm a descrição truncada (`MAX_DESCRICAO_CSV` em `data/extrair_livros_lexml.py`). Isso afeta o pré-preenchimento do sumário na Fase 4: o sumário que vem da `descricao` pode estar incompleto. Registrado no PLANO.
- **Leitor do /urn** às vezes devolve a hierarquia da CDDir repetida (também registrado).
- **Sondas em aberto** a decidir antes da 2.7: E estrito com fallback para OU quando o resultado é vazio (4 das 6 sondas dão "nenhum resultado"), indexar volume/artigos, plural via stemmer RSLP.

### Para ir além
- Manning, Raghavan e Schütze, *Introduction to Information Retrieval*, cap. 8 ("Evaluation in information retrieval"): conjuntos de teste, precisão, MRR, e por que a avaliação precisa de julgamentos humanos.
- Robertson e Zaragoza, "The Probabilistic Relevance Framework: BM25 and Beyond" (2009): a derivação do BM25F e a discussão sobre `k1`, `b` e os pesos por campo.
- Nocedal e Wright, *Numerical Optimization*, ou qualquer texto sobre *coordinate descent*: por que converge para ótimos locais e quando funciona bem.

### Perguntas
1. Com suas palavras: por que a métrica usa o empate pessimista (p = 1 + quantos outros têm nota ≥ à do esperado) em vez da posição que o motor devolve? Dê um exemplo concreto de "pontos por sorte".
2. Aplicação: multiplicar todos os pesos de campo por 2 e dividir `k1` por 2 muda o ranking? E se multiplicar só o peso do sumário por 2? Explique o papel do título fixo em 3 na varredura.
3. Raciocínio: a varredura mostrou que o peso do subtítulo, as categorias e o CDDir não mudam nenhuma consulta. Alguém propõe escrever em `ConsultasDeReferencia.swift` uma consulta nova que faça o peso das categorias "importar" e depois escolher o valor que a conserta. O que há de errado nisso, e qual é a ordem correta dos passos? Depois explique por que o ótimo (peso 0,5, `b` 0) foi rejeitado apesar de MRR 0,974, e por que a escolha do candidato A em vez do B também é uma decisão sobre risco, não só sobre número.

### Minhas respostas
(sem respostas)

---

## Tarefa 2.3i — Sondas da busca: plural, volume/artigos, correção de digitação, OU de reserva e peso do sumário 0,25 (2026-10-09)

### O que foi feito
Seis commits atacaram as seis sondas que a 2.3h deixou (#20 "arts 1710 1779", #21 "tratado 48", #22 "tratado direito privado", #23 "prisoes cautelares", #24 "procesos penal", #25 "lassalle"). Criaram `Singular.swift` (plural), `DistanciaDeEdicao.swift` (correção de digitação), passaram volume, rótulo e artigos para o campo subtítulo, deram ao `MotorDeBusca` o OU de reserva e a `RespostaBusca` (resultados, correções, modo), e baixaram o peso do sumário de 0,5 para 0,25. Os testes foram de 185 para 224, e as 29 consultas de ajuste ficaram todas em 1º lugar (Xcode 14.2, 0 falhas).

### Conceitos envolvidos

**1. Diagnóstico: por que "nenhum resultado"?** As quatro sondas vazias tinham a mesma causa. O motor usa **E estrito**: um livro só entra se tiver *todos* os termos. Basta um termo que não existe no vocabulário do índice (ou que existe em outra forma, como `prisoes` × `prisao`) para a interseção ficar vazia. Há duas frentes possíveis: fazer o termo existir (plural, volume/artigos, correção) ou relaxar o E (OU de reserva). A ordem escolhida foi o vocabulário primeiro e o OU por último, como rede de segurança: consertar a causa é melhor que esconder o sintoma.

```mermaid
flowchart TD
  C[consulta digitada] --> T[Tokenizador: palavras normalizadas]
  T --> S[Singular.forma em cada palavra]
  S --> D{termo desconhecido?<br/>df = 0, so letras, >= 5}
  D -- sim --> K[DistanciaDeEdicao: corrige para o termo do vocabulario]
  D -- nao --> E
  K --> E[E estrito: livros com TODOS os termos]
  E -- achou --> R[ranking BM25F]
  E -- vazio e >= 2 termos distintos --> O[OU de reserva: ordena por menos ausentes, depois nota]
  E -- vazio e 1 termo --> V[lista vazia]
```

**2. Stemming mínimo de plural (`Singular.swift`).** *Stemming* é reduzir palavras flexionadas a uma forma comum para que consulta e documento casem. Aqui o escopo é só plural, com regras da mais específica para a mais geral, aplicadas apenas a termos só de letras com 4 ou mais caracteres:

| Regra | Exemplos | Guarda |
| --- | --- | --- |
| oes -> ao | prisoes -> prisao, obrigacoes -> obrigacao | nenhuma |
| ais -> al | penais -> penal, reais -> real | exceções: mais, demais, jamais, pais (país), cais |
| eis -> el | imoveis -> imovel, papeis -> papel | 5 letras ou mais ("leis" não vira "lel": cai na regra geral e vira "lei") |
| ns -> m | ordens -> ordem, bens -> bem | nenhuma |
| vogal+res -> vogal+r | cautelares -> cautelar, credores -> credor | só depois de vogal ("livres" -> livre, "padres" -> padre) |
| zes -> z | juizes -> juiz, vezes -> vez | nenhuma |
| vogal+s -> tira o s | direitos -> direito, partes -> parte, leis -> lei | exceções: onus (viraria "onu", a ONU), virus, bonus, lapis |
| exceções fixas | arts -> art, civis -> civil | tabela testada |

Por que a ordem importa: "oes" tem de vir antes da regra geral de "s", senão "prisoes" viraria "prisoe". É o mesmo raciocínio de uma cadeia de `if` com casos mais específicos primeiro (como o *longest match* em tokenizadores).

A função entra **só no Tokenizador**: `termos(texto) = palavras(texto).map(Singular.forma)`. `palavras` continua sendo a forma escrita, já normalizada (minúscula, sem acento).

**A pergunta do Ricardo e a resposta.** Durante o planejamento ele perguntou: "a modificação acontece só ao tokenizar, sem alterar o que é armazenado? Isso não poderia produzir livros incorretos e incapacitar buscas, ou o plural força um padrão para todos?" A resposta, em partes:
- O texto gravado (Core Data, exportação, o que a tela mostra) **nunca muda**. O singular existe só nos *termos do índice em memória* (que é refeito ao abrir o app) e nos *termos da consulta*.
- Tem de valer **nos dois lados**. Se só a consulta virasse singular, "prisoes" -> `prisao` não casaria com o `prisoes` do índice, e a busca ficaria pior que antes. É a mesma ideia dos acentos: "Ação" vira `acao` no índice e na consulta.
- "Livro incorreto" não acontece: o índice é descartável e derivado, não há migração de dados. "Busca incapacitada" só ocorreria se índice e consulta usassem regras diferentes, o que é impossível usando a mesma função.
- O risco real é outro: o **falso positivo**, duas palavras diferentes caindo no mesmo termo (ex.: "ônus" -> `onu` colidiria com ONU). Por isso existe a tabela de exceções. Sim, o plural impõe um padrão a todos os termos; esse é o preço (aceito) de qualquer normalização.

**3. O problema do prefixo.** A busca "enquanto digita" usa prefixo no último termo. Com o vocabulário já no singular, quem digita "cautelare" não acharia nada, porque "cautelare" não é prefixo de `cautelar`: o resultado piscaria e sumiria no meio da palavra. Solução: o `IndiceInvertido` guarda também as **palavras escritas**, com contagem por livro (a contagem permite remover um livro sem apagar uma palavra que outro ainda usa). `termos(comPrefixo:)` procura o prefixo nas palavras escritas e devolve o termo já no singular: "caut" -> {cautelar, cautelares} -> {cautelar}. Se o prefixo já é um plural completo ("prisoes") e só o singular existe no índice, o singular volta também. O motor usa a palavra digitada para o prefixo e o termo singular para o resto.

**4. Distância de edição (`DistanciaDeEdicao.swift`).** Distância de Levenshtein = menor número de inserções, remoções e trocas de caractere para transformar uma palavra em outra. Aqui usa-se **Damerau-Levenshtein restrita** (OSA, *optimal string alignment*), que acrescenta a **transposição de vizinhas** como 1 operação, porque é o erro de digitação mais comum: "porcesso" -> "processo" = 1 (Levenshtein puro daria 2). "Restrita" significa que nenhuma substring é editada duas vezes: "ca" -> "abc" dá 3, enquanto a Damerau-Levenshtein completa daria 2. Para correção ortográfica a diferença quase nunca importa.

Implementação por programação dinâmica: `d[i][j]` = distância entre os i primeiros caracteres de A e os j primeiros de B. Guarda-se **três linhas** (atual, anterior e a de antes, necessária para a transposição) em vez da matriz inteira: memória O(m) em vez de O(n·m). Dois cortes (*early exit*):
- se os tamanhos diferem mais que o limite, nem calcula (não dá para consertar com menos edições que a diferença de tamanho);
- se o mínimo de uma linha passa do limite, para. Isso é seguro porque o mínimo de uma linha nunca é menor que o da anterior, nem com a transposição.

Custo total por termo desconhecido: O(V·n·m), com V o tamanho do vocabulário, e com os cortes na prática bem menor.

**5. Quando corrigir (no motor).**
- Só termo **desconhecido** (df = 0), só de letras, com 5 ou mais letras.
- Limite: 1 erro até 8 letras, 2 a partir de 9 (palavra curta com 2 erros vira qualquer outra palavra).
- O **último termo** só é corrigido se o prefixo não achou nada: "lassal" ainda está sendo digitado e não é erro.
- Desempate do candidato: menor distância, depois maior df, depois ordem alfabética. Em Swift, comparação de tuplas `(distancia, -df, termo)`; o `-df` inverte o sentido só dessa componente.
- Exemplos: "lassalle" -> `lassale` (1 remoção); "procesos" -> singular `proceso` -> `processo` (1 inserção), ou seja, o singular roda antes da correção.
- Se o termo corrigido repete um termo anterior ("processo procesos"), conta uma vez só.
- `buscar` agora devolve `RespostaBusca` (resultados + `correcoes: [Correcao(digitado, usado)]`) e tem `corrigir: Bool = true`: a tela poderá oferecer "buscar exatamente" (o "Você quis dizer" dos buscadores, no sentido inverso). As ~70 chamadas nos testes ganharam `.resultados` por script.

**Por que corrigir só termo desconhecido não piora consulta que funciona.** Um termo com df = 0 já fazia o E ficar vazio, então a consulta já não funcionava. Corrigir só pode transformar "vazio" em "algo". Nenhuma consulta que já retornava resultados é tocada, porque nenhum termo dela é desconhecido. Isso foi confirmado na medição: só #24 e #25 mudaram (ambas para 1º), todas as outras ficaram idênticas. Já corrigir também termos existentes ("pena" -> "penal") mudaria consultas certas, e por isso foi descartado.

**6. Volume, rótulo e artigos no campo subtítulo.** `volume` ("48"), `volumeRotulo` ("Tomo XLVIII" vira `tomo`, `xlviii`) e **só as pontas** dos artigos (1710 e 1779) entram no campo `subtitulo`, o mesmo papel da `parte`: texto de peso médio da folha de rosto, sem peso novo. Isso revisa a decisão de 09/10 que deixava `volumeRotulo` de fora. O intervalo inteiro foi descartado: seriam dezenas de números de ruído por livro, e "art 1750 -> vol XXIV" é busca por faixa, outro recurso. Ruído de "48": só bate com "48" isolado, pois "8.048" vira `8048` no tokenizador. Resultado: #20 e #21 em 1º; #13 "art 1710" subiu de nota (2,285 -> 3,068) com o item certo (o `melhorItem` olha só o sumário). Nova consulta #27 "tomo xlviii" -> T48, em 1º.

**7. OU de reserva e nível de coordenação.** Só dispara quando o E (já com filtro) devolve lista vazia **e** há 2 ou mais termos distintos. Entram os livros com pelo menos um termo. Nota = soma dos termos que o livro tem (na mesma ordem fixa do E, para a soma de `Double` ser reproduzível). Ordem: primeiro **menos palavras ausentes** (o *coordination level*, `coord` do Lucene antigo: premia quem cobre mais da consulta), depois nota, título, id. No modo E a chave "ausentes" vale 0 para todos, então a mesma função `ordenar` serve aos dois modos. Sem multiplicar a nota por fator de penalidade: E e OU nunca aparecem na mesma lista, então as notas só se comparam dentro do grupo. `RespostaBusca.modo` é `.todosOsTermos` ou `.parteDosTermos`; `ResultadoBusca.palavrasAusentes` traz a palavra **como o usuário escreveu**, na ordem da consulta ("prisões" aparece como "prisoes", não como o termo `prisao`), para a tela dizer "sem: stf". "prev prev" continua `[]` (só um termo distinto), o que responde a pergunta 2 da 2.3e.

### Por que assim
- **Vocabulário antes do OU:** o OU relaxa a precisão para todos; consertar o vocabulário só ajuda. O OU fica como rede.
- **Singular no Tokenizador, nos dois lados:** é o único ponto por onde texto vira termo; uma só função garante simetria.
- **Corrigir só df = 0:** garante por construção que não há regressão em consulta que já funcionava.
- **`corrigir: Bool` e `correcoes` na resposta:** a correção automática nunca deve ser silenciosa; a UI precisa mostrar o que foi feito e poder desfazer.
- **Nível de coordenação como primeira chave do OU:** com a soma de BM25 pura, um livro com um termo raro muito forte ganharia de um livro que tem todos os termos menos um.
- **Helper `comTodos` nos testes:** 4 testes do motor esperavam `[]` em consulta de 2 termos. Com o OU eles passariam a receber resultados. O helper devolve `[]` quando o modo é `parteDosTermos`, mantendo a intenção original do teste ("o E não achou nada"), e o OU tem testes próprios.
- **Testes cujas expectativas mudaram (intencional):** "Arts." -> `art`, comentarios -> `comentario`, vezes -> `vez`, obrigacoes -> `obrigacao`, recursos -> `recurso`, contratos -> `contrato`. No `BM25FTests`, o teste passava o termo cru "lopes" (agora o termo do índice é `lope`; sobrenomes também são singularizados, coerente nos dois lados) e passou a usar `Tokenizador.termos("Lopes")`.

**O conflito dos pisos e a decisão do peso (decisão do Ricardo).** Antes de medir o OU, foi escrita a consulta de risco #28 "prisao cautelar stf" -> fernandes ("stf" não existe no vocabulário e é curto demais para corrigir). Ela saiu em 2º, no mesmo padrão de #11 e #23: o Maluf ("Terrorismo e prisão cautelar": o termo em 3 itens do sumário) vence o título exato do Fernandes. O piso falhou (top1 0,923 < 0,94), o ponto combinado de parar e consultar. Varredura com 26 consultas de ajuste:

| peso do sumário | top1 | MRR | item | o que muda |
| --- | --- | --- | --- | --- |
| 0,5 (atual) | 0,923 | 0,962 | 1,000 | #11 e #28 em 2º (e a sonda #23) |
| 0,25 | 1,000 | 1,000 | 1,000 | #11, #23, #28 -> 1º |
| 1,5 ou mais | 0,846 | 0,923 | 1,000 | #1 e #24 caem |

Baixar o `b` do sumário abaixo de 0,75 de novo piorava o item da #19: a restrição do "item certo" funcionando como desenhada.

Por que a decisão da 2.3h mudou de figura: dos três motivos para descartar 0,25 lá, um (a #11 ser "caso misto") **caiu** com o plural, e os outros dois (ponta da grade; risco inverso não medido) continuavam. E #11, #23 e #28 são o **mesmo par** Fernandes × Maluf, não três evidências independentes: ganhar "três consultas" seria contar a mesma observação três vezes. A #23 deixa de ser sonda de qualquer jeito, porque a definição de sonda é "nenhum peso conserta", e agora um peso conserta.

Opções oferecidas ao Ricardo: (1, recomendada e escolhida) escrever **antes** 2 consultas de risco inverso, medir, e adotar 0,25 se não piorarem; senão manter 0,5 e baixar o piso num commit explicado. (2) manter 0,5 e baixar o piso. (3) adotar 0,25 já. As consultas de risco inverso, escritas antes de medir:
- #29 "direito fundamental liberdade" -> capez, item "O direito fundamental de liberdade" ("liberdade" também aparece no CDDir do Fernandes, e o Fernandes tem "direitos fundamentais" no sumário: baixar o sumário favorece o Fernandes).
- #30 "contrato individual" -> mello (sumário "contrato individual de trabalho"; o subtítulo do T48, peso 2, tem "Contrato..." e "dissídios coletivos e individuais").

Com 0,25, #29 e #30 continuam em 1º com o item certo, então 0,25 foi adotado. Varredura a partir de 0,25: nenhuma troca (ponto estacionário). Continua na ponta da grade, mas a grade **não** foi estendida: perseguir ganho além da ponta seria o sobreajuste que a 2.3h evitou. Os commits mostram a ordem honesta: o OU foi commitado sem a #28; a #28 entrou junto com a decisão do peso.

**Resultado final.** 29 consultas de ajuste, todas em 1º: top1 1,000, top3 1,000, MRR 1,000, item certo 1,000. Só a #22 continua sonda: é ambígua por natureza (os dois tomos são respostas certas); o conserto é a tela mostrar `volumeRotulo` na linha. Pisos novos: top1 >= 0,96 e MRR >= 0,98, um pouco abaixo de 1 para tolerar uma troca 1º <-> 2º (28/29 = 0,966; (28 + 0,5)/29 = 0,983), coerente com a rejeição do "um assert por consulta" da 2.3h, e nunca abaixo dos antigos (0,94 e 0,96).

### Alternativas descartadas
- **RSLP** (Orengo e Huyck, 2001; 8 etapas, ~200 regras): corta também derivação e junta "constitucional" com "constituição"; não dá para explicar por que duas palavras casaram; e quebra o prefixo (o radical nem sempre é prefixo do que o usuário digita).
- **Indexar as duas formas** (escrita e singular): dobraria a frequência dos termos e distorceria o IDF e o BM25.
- **Trigramas para correção:** exige um segundo índice; só compensa com vocabulário de milhões. Aqui o vocabulário é pequeno e a varredura com corte basta.
- **Deixar a correção para a Fase 5:** a Fase 5 é de sinônimos, outro problema.
- **Corrigir também termos existentes:** mudaria consultas que estavam certas.
- **Intervalo inteiro de artigos:** ruído; faixa é outro recurso.
- **OU sempre:** ruído em toda consulta. **Só ignorar termos desconhecidos:** não cobre "todos existem, mas ninguém tem todos". **Misturar E e OU com penalidade:** exige calibrar um fator e compara notas de grupos diferentes.
- **Adotar 0,25 de imediato (opção 3) ou manter 0,5 baixando o piso (opção 2):** a primeira decide sem medir o risco inverso; a segunda aceita uma regressão conhecida sem testar se havia custo em corrigi-la.
- **Estender a grade abaixo de 0,25:** sobreajuste.

### Padrões e boas práticas
- **Normalização simétrica:** tudo que se aplica ao índice deve ser aplicado à consulta pela mesma função. Quebra-se isso quando se transforma só um lado.
- **Derivado descartável:** o índice é derivação em memória de dados persistidos; por isso mudar a regra do plural não exige migração. Se o índice fosse persistido, mudar a regra exigiria reindexar.
- **Escrever o teste antes de medir (consulta de risco):** a consulta que pode refutar a sua hipótese precisa existir antes de você ver o número. Escrita depois, ela vira racionalização.
- **Parar no gatilho combinado:** o piso falhou e a execução parou para consultar. Piso sem consequência não é piso.
- **Interfaces de erro explícitas:** `RespostaBusca` com `correcoes` e `modo` em vez de o motor "adivinhar" calado.
- **Quando NÃO usar:** stemming por regras simples não serve para idiomas com morfologia mais rica sem tabela de exceções testada; correção automática não serve para vocabulário com muitos nomes próprios curtos (por isso o limite de 5 letras); OU de reserva não serve onde precisão importa mais que revocação (busca de documento específico).

### Armadilhas
- **Falso positivo do stemming:** duas palavras diferentes no mesmo termo ("ônus"/"onu"). Diagnóstico: um teste por exceção na tabela, e examinar o vocabulário quando o ranking surpreender.
- **Cadeia de regras fora de ordem:** colocar a regra geral de "s" antes de "oes" dá "prisoe". Os testes por regra pegam isso.
- **Expectativa de teste que "muda de significado":** os testes do E que passaram a receber resultados do OU teriam passado silenciosamente se o helper `comTodos` não existisse. Cuidado ao alterar o contrato de uma função sem rever quem testava o caso vazio.
- **Mudança de IDF por stemming:** `cautelares` (raro, só no Capez) virou `cautelar` (mais comum) e perdeu IDF; por isso a #11 foi do 3º para o 2º (Capez caiu para 3º: maluf 3,134 | fernandes 3,108 | capez 2,832). A parte "estrutural" prevista no caso misto da 2.3h se confirmou. Moral: normalizar o vocabulário altera as estatísticas globais, não só o casamento.
- **Contar três vezes a mesma evidência** (#11, #23, #28).
- **Ponta da grade:** 0,25 continua lá. Uma amostra de 29 consultas (1 consulta = 1/29, cerca de 3,4 pontos de top1) com "tudo 1,000" é sinal de que o conjunto ficou fácil para este motor, **não prova**. Novas consultas devem vir do uso real, na tarefa 2.7.
- **Transposição e linhas de DP:** confundir qual das três linhas guarda `i-2` é o bug clássico da OSA com memória reduzida.

### Para ir além
- Manning, Raghavan e Schütze, *Introduction to Information Retrieval*, cap. 3 (tolerant retrieval: distância de edição, k-gramas) e cap. 2.2.4 (stemming e lematização), disponível online no site da Stanford.
- Orengo e Huyck, "A Stemming Algorithm for the Portuguese Language" (2001): o RSLP, para entender o que foi descartado e por quê.
- Damerau (1964) e Wagner e Fischer (1974): origem da distância de edição por programação dinâmica; para o `coord` e a pontuação por termos presentes, a documentação do `ClassicSimilarity` do Lucene (verifique a versão que usar).

### Perguntas
1. Com suas palavras: por que o singular precisa ser aplicado nos dois lados (índice e consulta), e por que o prefixo exige guardar também as palavras escritas? Dê o exemplo de "cautelare".
2. Aplicação: hoje só se corrige termo com df = 0. Se alguém propusesse corrigir também termos existentes quando o resultado fosse "fraco", que consulta do conjunto atual poderia piorar e como você testaria a hipótese sem sobreajustar? E o que mudaria no motor se o limite de 5 letras caísse para 3?
3. Raciocínio: por que #11, #23 e #28 não contam como três evidências a favor do peso 0,25? Por que as consultas de risco inverso (#29 e #30) tinham de ser escritas **antes** de medir? E "tudo em 1,000" é motivo para comemorar ou para desconfiar? Justifique.

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

(sem respostas)

---

## Tarefa 2.4a — Montagem das dependências e tela inicial com as estantes (2026-10-09)

### O que foi feito
Criamos `App/Dependencias.swift` (a montagem: escolhe a implementação da porta), o `InicioViewModel` com seu `enum Estado` e a `InicioView` (grade de estantes, criar e renomear). `EstantesApp` passou a guardar um `Result` para não travar se o banco não abrir. Para ver as telas no simulador, há exemplos só em DEBUG (`App/Exemplos.swift`), o `scripts/capturar.sh` e um repositório falso nos testes (`BibliotecaRepositorioEmMemoria`). Antes disso, o PLANO registrou a forma de trabalho das telas: primeiro a lógica (2.4a-e) com componentes nativos, depois o estilo tela por tela.

### Conceitos envolvidos
**Raiz de composição e injeção de dependência.** Em vez de cada tela criar o que precisa, um único lugar (`Dependencias`) decide "a porta `BibliotecaRepositorio` é o Core Data". As telas recebem o ViewModel pronto, e o ViewModel recebe o repositório pelo `init`. Isso é a *composition root*: só ali o código concreto é conhecido, e o resto depende do protocolo. Ganho prático: nos testes entra o falso; nos previews e nas capturas, o Core Data em memória; em produção, o disco. Nada muda nas telas.

**Estado como `enum` com valores associados.** `Estado` tem quatro casos (`carregando`, `vazio`, `pronto([...])`, `erro(String)`). Com `Bool`s (`carregando`, `temErro`, `lista`) haveria 2^n combinações, e a maioria seria absurda ("carregando e com erro"). O enum torna os estados impossíveis **irrepresentáveis**: o compilador obriga o `switch` da View a tratar todos. Princípio: "make illegal states unrepresentable".

**`@StateObject` e ciclo de vida.** A View é um valor barato que o SwiftUI recria muitas vezes; o que precisa sobreviver é o ViewModel. `@StateObject` guarda o objeto fora da View e só executa a expressão de criação na primeira vez. Por isso o `init` recebe `@autoclosure`: `InicioView(viewModel: deps.fazerInicioViewModel())` não cria nada na hora; vira um closure que o `StateObject` chama uma vez. Com `@ObservedObject` o ViewModel seria recriado a cada reconstrução da View e o estado se perderia.

**`@MainActor`.** `@Published` alimenta a UI, então só pode mudar na thread principal. Marcar o ViewModel como `@MainActor` faz o compilador garantir isso. O custo apareceu no Xcode 14.2: *"call to main actor-isolated instance method ... in a synchronous nonisolated context"*. Naquele SDK só o `body` da `View` é `@MainActor`; propriedades auxiliares da View não são. Quem cria um objeto `@MainActor` precisa estar no main actor também, então a solução foi `@MainActor` na `RaizView` e no tipo do closure (`@MainActor (Dependencias) -> Conteudo`). Em SDKs mais novos a `View` inteira é `@MainActor`, então isso é uma diferença entre os dois Xcodes que o projeto precisa suportar. Esta é uma observação do que o compilador disse; para detalhes de versão confirme nas notas de lançamento do SDK.

**`Binding` derivado.** O alerta precisa de `Binding<Bool>`, mas o estado real é `pedido: PedidoDeNome?` (nil = fechado). Construímos o `Binding` a partir do opcional (`get: pedido != nil`, `set: se false, pedido = nil`). Assim há **uma só fonte de verdade**; guardar também um `Bool` obrigaria a mantê-los sincronizados.

**Tela derivada do banco.** Depois de gravar, o ViewModel chama `carregar()` de novo. Não há `@FetchRequest` nem lista editada na mão. O custo é reler; o ganho é que a tela nunca diverge do que está salvo. Com poucas estantes, o custo é desprezível.

**Contagem: N+1 consultas.** `carregar()` faz 1 consulta de estantes + 1 `quantidadeDeLivros` por estante (N+1). É o padrão que costuma ser um problema com milhares de linhas ou rede. Aqui é aceitável porque N é pequeno, a consulta é um `COUNT` no SQLite local (não carrega livros) e não há latência de rede. Uma consulta agregada (`GROUP BY`) só valeria com muitas estantes.

**Argumentos de lançamento e `UserDefaults`.** O iOS registra argumentos do tipo `-chave valor` no domínio de argumentos do `UserDefaults`. Então `-captura Inicio` é lido com `UserDefaults.standard.string(forKey: "captura")`, sem parser. Isso, mais `#if DEBUG`, permite abrir qualquer tela já preenchida (o `simctl` não toca na tela).

**Dublê de teste (fake).** `BibliotecaRepositorioEmMemoria` é um *fake*: implementação funcional simplificada (dicionários) com chaves `falharAoLer`/`falharAoGravar` para forçar erros. Difere de um *mock* (que verifica chamadas). Precisa seguir o **contrato** da porta (cascata, mover, destino inválido), senão os testes passam contra um comportamento que o repositório real não tem.

### Por que assim
- `Dependencias` como `struct` criada uma vez, com `producao()` e `emMemoria()`: é visível e testável, e a injeção ocorre pelo `init`, como pede o PLANO.
- `Result { try Dependencias.producao() }` no `EstantesApp`: se o banco falha (disco cheio, migração quebrada), mostra `MensagemDeErroView` em vez de `try!` (que derruba o app sem explicação).
- `EstanteResumo` na Apresentação: a contagem é dado da tela; pôr `quantidade` em `Estante` poluiria o Domínio com algo derivado.
- Erro de gravação em `mensagemDeErro`, separado de `estado`: se virasse `.erro`, a lista sumiria por causa de uma falha que não a invalida.
- `nomeValido` estático, usado pelo ViewModel **e** pela View: uma regra, dois usos; a View só desabilita o botão, o ViewModel é quem de fato recusa.
- Exemplos em `App/` e só em DEBUG: montar um repositório concreto é papel da montagem, e o código de exemplo não deve ir para o `.ipa` de produção.
- Previews com o Core Data em memória real: um segundo falso dentro do app seria código a manter só para previews.

### Alternativas descartadas
- **Singleton `.shared`:** esconde de quem depende de quê, e testes compartilham estado global.
- **`.environmentObject`:** funciona, mas a dependência fica implícita (falta de um objeto só aparece em tempo de execução, com crash); o PLANO pede injeção pelo `init`.
- **`@FetchRequest`:** acopla a View ao `NSManagedObject`, o que o projeto proíbe fora de `Dados/Persistencia/`.
- **Vários `Bool` no estado:** estados impossíveis possíveis.
- **Consulta agregada de contagens:** otimização prematura aqui.
- **Override da barra de status (9:41) nas capturas:** tentado; o simulador do iOS 16 ignorou o `--time`. Retirado em vez de mantido como código morto.

### Padrões e boas práticas
- **Composition root + injeção por construtor.** Não use quando o objeto não tem variação nenhuma e é puro (uma função utilitária estática não precisa de injeção).
- **MVVM com estado em enum.** Quando o estado é realmente independente (dois alertas sem relação), campos separados são mais honestos que um enum forçado.
- **Fake com contrato** em vez de mock verificador, para testar comportamento e não implementação.
- **Trabalhar em duas passadas (lógica, depois estilo):** evita retrabalho de estilo sobre uma lógica que ainda muda. Cada captura tem versão (0.x lógica, 1.x+ estilo) para comparar.
- **Parar com margem de uso:** registrar o estado no PLANO antes de acabar o limite, para que a próxima sessão retome sem contexto.

### Armadilhas
- **Isolamento de ator diferente entre SDKs:** compila no Xcode 26 e falha no 14.2 (ou o contrário). Sempre rode `./scripts/testar.sh` no Mac e olhe a CI.
- **`@StateObject` sem `@autoclosure`:** se o init avaliar `InicioViewModel(...)` direto, cria-se um ViewModel descartado a cada reconstrução da View (o `StateObject` ignora, mas o custo de criação ocorre).
- **`.task` repetido:** `.task` roda quando a View aparece; se ela reaparecer, recarrega. Aqui é benigno, mas em telas pesadas vale controlar.
- **Banco em memória é assíncrono para preencher:** por isso `ComExemplos` espera os dados antes de mostrar a tela; senão a captura sai vazia (condição de corrida).
- **Argumento de lançamento perdido:** configurado no Edit Scheme do Xcode, some quando o `xcodegen generate` recria o projeto.
- **Fake que diverge do real:** se o contrato mudar no repositório Core Data e o fake não acompanhar, os testes do ViewModel mentem. Idealmente os mesmos testes de contrato rodariam nos dois.

### Para ir além
- Documentação da Apple: *Managing model data in your app* e *StateObject* (developer.apple.com/documentation/swiftui), para o ciclo de vida de `@StateObject` vs `@ObservedObject`.
- Mark Seemann, *Dependency Injection: Principles, Practices, and Patterns* (capítulo sobre Composition Root).
- Yaron Minsky, "Effective ML" (a ideia de "make illegal states unrepresentable"), disponível como palestra e artigo.

### Perguntas
1. Com suas palavras: por que o `InicioViewModel` recebe o repositório pelo `init` e quem o monta é `Dependencias`? O que você ganha nos testes e nos previews?
2. Aplicação: o PLANO pede que a tela de uma estante mostre os livros. Se `InicioViewModel.carregar()` precisasse também do total de livros "sem estante", em que ponto do código você faria isso e o que mudaria no `enum Estado`? Quando a estratégia N+1 deixaria de ser aceitável?
3. Raciocínio: por que uma falha ao gravar vira `mensagemDeErro` e não `.erro(...)` no estado? Que comportamento ruim o usuário veria se fosse `.erro`? E por que o `@autoclosure` no `init` da View evita o ViewModel ser recriado?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

(sem respostas)

---

## Tarefa 2.4b — Exclusão de estante com confirmação (e correção do botão Salvar) (2026-10-09)

### O que foi feito
Dois commits. O primeiro (76c8289) corrige o alerta "Nova estante", que só mostrava "Cancelar". O segundo (bf36e14) adiciona "Apagar" ao menu de contexto da estante: o `InicioViewModel` monta um `PedidoDeExclusao` (estante, quantidade atual de livros, destinos possíveis) e a `InicioView` o apresenta em um `confirmationDialog` com até duas folhas (confirmar; escolher a estante de destino). Foram 7 testes novos (242 verdes no Xcode 14.2), e o `capturar.sh` ganhou `EXTRA="-chave valor"`.

### Conceitos envolvidos
**Defeito de componente do sistema que o teste de ViewModel não vê.** No iOS 16, o `.alert` do SwiftUI *esconde* (não acinzenta) um botão com `.disabled(true)` e não reavalia os botões enquanto o usuário digita. O campo começava vazio, então o Salvar nascia desabilitado e sumia. Ao renomear, o campo já vinha preenchido e o botão aparecia. O ViewModel estava correto; o defeito estava na camada de apresentação, onde só olhar a tela (e o caso "começa vazio") revela. A correção foi remover o `.disabled` e deixar a proteção contra nome vazio só no ViewModel (`nomeValido`), que já tinha teste. Isso é coerente com a regra: a View é só uma casca; a regra mora onde é testável.

**Estado de interface vs. estado de ViewModel.** Um `confirmationDialog` com `presenting:` amarra a visibilidade a um valor. Quando o usuário toca numa ação, o SwiftUI fecha a folha e zera o binding dela. Se o `PedidoDeExclusao` estivesse nesse binding, sumiria antes da segunda folha (escolher destino) abrir. Por isso o ViewModel *devolve* o pedido (`pedidoDeExclusao(de:) async -> PedidoDeExclusao?`) e a tela guarda `exclusao` + dois `Bool` (`confirmandoExclusao`, `escolhendoDestino`). A pergunta "qual folha está aberta?" é estado de apresentação; "o que será apagado e para onde podem ir os livros?" é dado do pedido. Separar os dois evita o acoplamento ao ciclo de vida da folha.

**Dado fresco em ação destrutiva.** A quantidade de livros é relida do banco ao preparar o pedido, não tomada do cartão da grade (que pode estar desatualizado). Numa confirmação do tipo "apagar a estante e os 3 livros", o número mostrado precisa ser o real naquele instante, senão o usuário consente com informação errada.

**Defesa em profundidade.** `destinosPossiveis` nunca inclui a própria estante (a interface nem oferece a opção), e o repositório mantém a trava `destinoInvalido` (já existente desde a 2.2). Duas camadas independentes: se uma tiver um bug, a outra segura. Não é redundância gratuita: a primeira serve ao usuário (não oferecer opção inválida), a segunda protege os dados.

**Modelar os casos como propriedade derivada.** `podeMover` = há livros *e* há outra estante. Os três casos do diálogo (vazia; com livros e com destino; com livros sem destino) saem de duas informações simples, e o texto muda de acordo. `textoDaQuantidade(_:comArtigo:)` usa `switch` sobre tupla `(quantidade, comArtigo)` para produzir "1 livro", "3 livros", "o livro", "os 3 livros". Pluralização é uma tabela pequena; o `switch` sobre tupla deixa o compilador conferir a exaustividade.

**Ação de lançamento só para captura.** `InicioView.AcaoInicial` (novaEstante, apagar, escolherDestino) roda no `.task` depois de carregar. O `simctl` não toca na tela, então é a forma de fotografar um alerta aberto. Fica atrás de `#if DEBUG` com o resto dos exemplos.

### Por que assim
- **ViewModel devolve o pedido em vez de guardá-lo em `@Published`:** o ciclo de vida da folha é da tela (ver acima).
- **Menu de contexto com `role: .destructive`:** o sistema pinta de vermelho e sinaliza a ação perigosa sem estilo próprio.
- **Mover vs. apagar tudo como escolhas explícitas:** o usuário nunca perde livros sem ler o número no botão vermelho.
- **Sem teste para "Cancelar":** Cancelar não chama o ViewModel; não há comportamento nosso para verificar. Testar o nada só criaria falsa confiança.
- **Corrigir o Salvar removendo `.disabled`, e não trocando o alerta por sheet:** a sheet com `Form` é decisão de estilo, adiada para a etapa de estilo (o PLANO separa lógica de estilo).

### Alternativas descartadas
- **Swipe para apagar:** não existe em grade (só em `List`).
- **Modo "Editar" com ✕ em cada cartão:** um passo a mais para uma ação rara.
- **Diálogo único com um botão por destino:** fica enorme com muitas estantes.
- **Guardar o pedido num `@Published` do ViewModel:** zerado pelo binding antes da segunda folha.
- **Usar a quantidade do cartão:** pode estar defasada.

### Padrões e boas práticas
- **Confirmação proporcional ao dano:** estante vazia pede só confirmação simples; com livros, mostra o número. Não use confirmação para ações reversíveis (melhor oferecer "desfazer").
- **Defesa em profundidade** em operações destrutivas. Não duplique regra complexa nas duas camadas: aqui a segunda é uma checagem simples de invariante.
- **Reproduzir o bug antes de corrigir** (aqui, abrindo o alerta via argumento de lançamento): confirma a causa em vez de supor.

### Armadilhas
- **Teste verde não significa tela correta:** o bug do Salvar passou por 235 testes verdes. Casos que começam vazios, estados iniciais e transições entre folhas precisam ser vistos.
- **Comportamento muda entre versões do iOS:** o `.alert` do iOS 16 pode se comportar diferente do iOS 26 (a CI). Não assuma; veja nos dois quando importar. Confirme o comportamento exato nas notas do SDK, pois aqui só observamos o simulador.
- **Estado zerado ao tocar uma ação:** em `confirmationDialog`/`alert`, o binding é zerado ao fechar. Qualquer dado necessário depois deve ficar fora dele.
- **A captura estática não prova a transição** entre as duas folhas; foi preciso o teste manual do Ricardo.

### Para ir além
- Documentação da Apple: `confirmationDialog(_:isPresented:titleVisibility:presenting:actions:message:)` e *Human Interface Guidelines: Alerts / Action sheets*.
- Martin Fowler, "Test Double" (martinfowler.com/bliki/TestDouble.html), para fake vs. mock já usado nos testes do ViewModel.

### Perguntas
1. Com suas palavras: por que o `PedidoDeExclusao` não fica num `@Published` do ViewModel, e quem guarda "qual folha está aberta"?
2. Aplicação: se o app passasse a permitir mover livros para uma estante *dentro* de outra (estantes aninhadas), o que mudaria em `destinosPossiveis` e na trava `destinoInvalido`? Haveria um novo caso inválido?
3. Raciocínio: o bug do Salvar tinha 235 testes verdes por cima. Por que nenhum o pegou, e que tipo de teste (ou prática) pegaria? Por que o caso "renomear" funcionava e o "criar" não?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

(sem respostas)

---

## Tarefa 2.4c — Estante → livros agrupados por prateleira → detalhe (2026-10-09)

### O que foi feito
Nasceu a regra pura `AgrupamentoPorPrateleira` (`Dominio/Regras`, 9 testes), que transforma a lista de livros de uma estante em grupos por prateleira. Sobre ela vieram `EstanteViewModel` + `EstanteView` (lista com uma `Section` por prateleira) e `LivroDetalheViewModel` + tela de detalhe (com apagar). A navegação foi movida da `InicioView` para `App/NavegacaoView.swift`, usando `NavigationLink(value:)` e `navigationDestination(for:)`. Foram 24 testes novos (266 verdes no Xcode 14.2) e o idioma do app passou a ser pt-BR.

### Conceitos envolvidos

**Agrupar por chave canônica, exibir a grafia mais comum.** "Caixa azul", "caixa azul " e "Cáixa Azul" são a mesma prateleira para o usuário. O agrupamento usa `Normalizacao.chave` (a mesma normalização da busca: minúsculas, sem acento, sem espaços nas pontas) como chave de um dicionário. É o padrão *group by* clássico: uma passada, O(n) para montar os grupos com hash, depois O(g log g) para ordenar os g grupos. O título exibido é a grafia mais usada dentro do grupo (uma contagem por grafia); no empate vale a menor na ordem dos caracteres. Sem esse desempate, o resultado dependeria da ordem de iteração do dicionário, que em Swift é aleatória entre execuções (hash seeding por processo), e o teste ficaria intermitente. Regra geral: **toda ordenação precisa de critério total**, senão o resultado não é determinístico.

**Comparar `String` em Swift.** `String` compara por escalares Unicode canonicamente equivalentes, mas a ordem não é a "do dicionário": "C" < "c" (maiúsculas vêm antes) e "a" < "á". Foi o erro que apareceu na escrita do teste: o valor esperado precisa ser calculado à mão, não deduzido por intuição. Para ordem que o usuário percebe como natural, usa-se `localizedStandardCompare`, que é o mesmo comparador do Finder: trata números dentro do texto como números ("2ª de cima" < "10ª de cima"), ignora diferenças de caixa/acento de forma sensível ao idioma. Cuidado: ele depende do *locale*, então testes que o usam herdam esse comportamento.

**Ordenação com chave composta e `Int.min`.** Dentro do grupo: título normalizado, volume, ano, id. Para "sem volume primeiro", usa-se `volume ?? Int.min` (um `nil` vira o menor inteiro possível). É um truque comum para ordenar opcionais; funciona porque nenhum volume real vale `Int.min`. O `id` fecha o critério só para ser determinístico (ordem total), não por significado.

**Inversão de dependência na navegação.** Esta é a decisão arquitetural central da tarefa. As telas de destino precisam de ViewModels, que precisam de repositórios, que são montados no `Dependencias` (camada App). Se a `InicioView` (Apresentação) construísse a `EstanteView`, Apresentação passaria a conhecer a montagem, invertendo a direção das camadas. Solução: as telas só emitem *valores* (`NavigationLink(value: estante)`), e quem conhece as fábricas (`NavegacaoView`) declara `navigationDestination(for: Estante.self) { ... }`. A tela diz "quero ir para esta estante"; a raiz de composição decide *como* construir o destino. É o mesmo princípio da composition root: só um lugar conhece as classes concretas.

```mermaid
flowchart LR
    A[App/NavegacaoView<br/>navigationDestination + Dependencias] --> B[InicioView]
    A --> C[EstanteView]
    A --> D[LivroDetalheView]
    B -. NavigationLink value: Estante .-> A
    C -. NavigationLink value: RotaDoLivro .-> A
```

**Navegação por valor (iOS 16).** A `NavigationStack` mantém um *caminho* (lista de valores `Hashable`). `NavigationLink(destination:)` constrói o destino de cada linha ao desenhar a lista (trabalho e inicializações desperdiçados, inclusive `init` de ViewModels). `NavigationLink(value:)` guarda só o valor; o destino é construído quando se navega. Bônus: o caminho é dado, então pode-se abrir já empurrado (`NavigationPath` inicial), o que as capturas usam. Exige `Hashable`, por isso `Estante` deixou de ser só `Equatable`: `Hashable` implica `Equatable` e a conformidade sintetizada funciona quando todos os campos são `Hashable`.

**Tipo de rota próprio.** `RotaDoLivro(livroId:)` em vez de `UUID`: `navigationDestination(for: UUID.self)` capturaria qualquer `UUID` empurrado na pilha, de qualquer tela. Um tipo-rota dá um canal tipado e sem ambiguidade. E leva só o id: se a rota carregasse o `Livro` inteiro, a cópia ficaria velha após uma edição (structs são valores copiados). O detalhe relê do banco, então a fonte da verdade é uma só.

**`.onAppear` × `.task` na pilha.** Ao voltar de uma tela filha, a tela de baixo reaparece, mas o `.task` não roda de novo (a view nunca saiu da hierarquia). O `.aoVoltar { }` é um `ViewModifier` com uma flag `jaApareceu`: ignora o primeiro `onAppear` (que já é coberto pelo `.task`) e executa nos seguintes. Exige `@State` para a flag, pois a struct da View é recriada e só `@State` sobrevive.

**Estado de tela como enum.** Os dois ViewModels expõem `carregando / vazia / pronta / erro` (e `naoEncontrado` no detalhe). Um enum torna estados impossíveis impossíveis de representar (carregando e com erro ao mesmo tempo), ao contrário de três `Bool`.

**Mapeamento Modelo → seções de exibição.** `secoes(de:)` (estático e puro) monta `SecaoDoLivro/CampoDoLivro` só com campos preenchidos; vazio ou só espaços some, e seção sem campos some. A decisão "o que mostrar" fica testável sem SwiftUI. `textoDosArtigos` usa `switch` sobre tupla de opcionais, em que o compilador verifica exaustividade. `LabeledContent` (iOS 16) dá o par rótulo/valor padrão do sistema.

**Idioma de desenvolvimento.** A captura mostrou "Back". O iOS escolhe a localização do sistema (botão Voltar, "Cancelar" da busca etc.) comparando os idiomas do usuário com as localizações que o *bundle* declara. Sem `CFBundleDevelopmentRegion` explícito, o app caía em inglês. `developmentLanguage: pt-BR` no XcodeGen e `CFBundleDevelopmentRegion: pt-BR` no Info.plist resolveram. Quem aprende: o idioma dos textos *do sistema* é decisão do app, não só dos textos que você escreve.

### Por que assim
- **Agrupamento no Domínio:** sem SwiftUI, testa em milissegundos; reaproveitável (futura exportação, outra tela).
- **Navegação na raiz de composição:** mantém a regra "Apresentação não conhece montagem".
- **`apagar() -> Bool` e a tela chama `dismiss()`:** o ViewModel não conhece o ambiente de navegação; ele informa o resultado, a View decide como reagir.
- **Reler o banco ao voltar:** custa milissegundos num banco local e elimina a sincronização entre telas.
- **Botões "+" e "Editar" desabilitados:** o escopo vai até o 2.4d, sem funcionalidade pela metade.

### Alternativas descartadas
- **`NavigationLink(destination:)`:** constrói destinos cedo e acopla a tela à fábrica.
- **Closures ou notificações para avisar a tela anterior de mudanças:** acoplam telas entre si; reler é mais simples.
- **Passar o `Livro` na rota:** cópia desatualizada.
- **Arquivo `Navegacao.swift` em App:** já existe `Componentes/Navegacao.swift`; o Xcode recusa dois arquivos com o mesmo nome no mesmo alvo (os produtos `.o` colidem). Por isso `NavegacaoView.swift`.
- **Ordenar prateleiras com `<` simples:** colocaria "10ª" antes de "2ª".

### Padrões e boas práticas
- **Composition root** e **inversão de dependência**: a montagem em um só lugar. Não vale a pena em apps minúsculos; aqui compensa porque há testes e camadas.
- **Ordem total determinística** em toda ordenação; teste com dados que provoquem empate.
- **Função estática pura para formatar/mapear** e testar sem a View.
- **Reproduzir visualmente**: a captura achou o "Back" que nenhum teste acharia.

### Armadilhas
- **Ordem de iteração de `Dictionary`/`Set`** é indefinida: nunca deixe o resultado depender dela.
- **`localizedStandardCompare` depende do locale** do processo; teste na CI (Xcode 26) pode divergir se o locale for outro.
- **`navigationDestination` dentro de uma `List` preguiçosa** ou fora da pilha pode não ser registrado; o lugar seguro é perto da raiz (como aqui). Confirme na documentação da Apple se mudar.
- **`onAppear` roda mais de uma vez** (reaparição, voltar de sheet); ações com efeito colateral precisam de proteção.
- **Captura com toque simultâneo no simulador** gera imagem errada; refaça, não interprete.

### Para ir além
- Documentação Apple: *NavigationStack*, *navigationDestination(for:destination:)* e *NavigationPath*.
- Mark Seemann, *Dependency Injection: Principles, Practices, and Patterns* (capítulo sobre Composition Root).
- Documentação Apple: *String Comparison* (`localizedStandardCompare`) e *Internationalization and Localization Guide* (idioma de desenvolvimento do bundle).

### Perguntas
1. Com suas palavras: por que a `InicioView` não constrói a `EstanteView` diretamente, e o que a `NavegacaoView` faz que ela não pode fazer?
2. Aplicação: se o usuário pudesse ter duas prateleiras "Direito Civil" e "Direito civil" e quisesse que fossem *distintas*, o que mudaria no agrupamento? Que efeito isso teria na busca, que usa a mesma `Normalizacao.chave`?
3. Raciocínio: o que aconteceria na ordem dos grupos se o desempate da grafia exibida fosse "a primeira encontrada" e a lista de livros viesse do banco em ordem não garantida? E por que `.aoVoltar` ignora o primeiro `onAppear`?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

(sem respostas)

---

## Tarefa 2.4d — Formulário de adicionar e editar livro (2026-10-10)

### O que foi feito
Criamos a regra `RascunhoLivro` em `Dominio/Regras/` (só Foundation, 17 testes): o livro como o formulário o edita, com validação e conversão para `Livro`. Sobre ela veio o `LivroFormularioViewModel` (modos `.novo(estanteId)` e `.edicao(livroId)`, 10 testes) e a `LivroFormularioView`, uma folha (`sheet`) com `NavigationStack` próprio. Junto, a `FolhaPendente` em `App/NavegacaoView.swift`, que decide qual tela abre uma folha por pedido das capturas. O total foi de 266 para 293 testes.

### Conceitos envolvidos

**Rascunho (draft) como tipo próprio.** Formulário não edita o modelo; edita uma *cópia de trabalho* que pode estar inválida. `RascunhoLivro` guarda tudo como `String` (e `autores: [String]`). Motivo: se o campo "ano" fosse `Int?`, digitar "20a" não teria representação, e a tela só saberia dizer "vazio". Com texto, o estado intermediário existe, a regra o aponta (`numeroInvalido`) e a conversão para `Int` acontece uma única vez, em `montar`. É o princípio "parse, don't validate" aplicado ao limite entre a interface e o domínio: dentro do domínio os tipos já são os certos; na borda, texto.

```mermaid
flowchart LR
    T[Campos de texto] --> R[RascunhoLivro<br/>Strings]
    R -->|problemas| E[Campo: Problema<br/>mensagens na tela]
    R -->|montar sobre base| L[Livro<br/>Int, nil, UUID]
    L --> P[(Repositório / Core Data)]
```

**Validação de número com ponto de milhar.** A regra: inteiro > 0, com ponto só *entre dígitos* ("1.710", como artigos aparecem impressos). Rejeita "1..710", ".710", "710." e "½". Detalhe importante: `Character.isNumber` é verdadeiro para "½", "٣" (dígito árabe) e outros; o `Int(...)` depois falharia ou, pior, a regra aceitaria lixo. Por isso a função própria `isASCIIDigit` (compara com "0"..."9"). Overflow (`Int("99999999999999999999")` devolve `nil`) também vira erro, em vez de crash. Lição geral: `isNumber`, `isLetter` etc. seguem o Unicode; para formato de dado, defina o alfabeto explicitamente.

**Edição preserva o que o formulário não mostra.** `montar(sobre base: Livro?)` parte do livro existente e sobrescreve só os campos editáveis. Assim `id`, `adicionadoEm`, `origem`, `itensSumario`, `categoriaIds`, `cddir`, `cddirCaminho` e `urn` sobrevivem. Se o formulário montasse um `Livro` do zero, salvar apagaria o sumário e a classificação sem ninguém notar (perda silenciosa de dados). Livro novo recebe `origem = .manual`.

**Vários autores em camadas.** A mesma informação tem forma diferente em cada camada, e cada forma serve ao seu trabalho:

| Camada | Forma | Por quê |
| --- | --- | --- |
| Domínio / formulário | `[String]` | a ordem importa (primeiro autor) e a lista é natural |
| Core Data | uma `String`, um nome por linha | sem entidade `Autor` (decisão da 2.2): evita relação e junção para um dado que só se exibe e se busca |
| Detalhe | rótulo "Autor" ou "Autores" | muda conforme a quantidade |
| Busca | campo `autor` com peso baixo | no BM25F, autor ajuda mas não deve superar o título |

Para a tela havia duas opções. (1) Lista de campos, uma linha por autor, como no app Contatos: não depende da tecla Return e cada nome é inequívoco. (2) Uma caixa multilinha: mais simples, mas Return confunde no iPhone e "Fulano e Beltrano" viraria um autor só. Escolhemos a (1). Papel do autor (coordenador, organizador) ficou fora do escopo.

**Obrigatoriedade só na borda.** O plano dizia "só título". Recomendei isso porque o cadastro manual existe justamente para o livro com dados faltando. O Ricardo escolheu título + autor + editora + ano. Consequência: a exigência vive apenas no formulário (`problemas()`); `Livro`, Core Data e JSON continuam com esses campos opcionais. Razão: LexML, Google Books e Gemini (Fase 3) e livros antigos podem não trazer editora ou ano, e se o banco exigisse, a importação falharia. Efeito colateral aceito: editar um livro importado sem editora/ano obriga a completá-los antes de salvar. É o princípio de "validação depende do contexto": a mesma entidade tem regras diferentes conforme a porta de entrada.

**Erros só depois da primeira tentativa.** `tentouSalvar` evita mostrar vermelho num formulário recém-aberto (ninguém digitou nada ainda). Depois da primeira tentativa, a validação é ao vivo.

**`alterado` e `interactiveDismissDisabled`.** `alterado` é `rascunho != inicial` (exige `Equatable`). Enquanto há mudanças, `.interactiveDismissDisabled(alterado)` impede fechar a folha arrastando e perder o que foi digitado; Cancelar continua disponível.

**Reordenar e remover sem o SwiftUI.** `remove(atOffsets:)` e `move(fromOffsets:toOffset:)` são extensões do SwiftUI, e o ViewModel só importa Foundation; reescrevemos à mão. A convenção do `onMove` é traiçoeira: o `toOffset` é a posição *antes* de retirar os itens movidos. Mover o índice 0 para `toOffset` 2 em `[A,B,C]` dá `[B,A,C]` (a posição final é 1, não 2). Regra prática: se `toOffset > origem`, subtrai-se o número de itens movidos que estavam antes do destino. Testamos 6 casos.

**Binding por posição.** Cada campo de autor usa um `Binding` construído por índice. Ao apagar uma linha, o SwiftUI pode ainda avaliar o binding do índice antigo, já fora do array; o getter/setter precisa tolerar isso (devolver "" e ignorar), senão há crash de índice fora dos limites.

**Fábrica por closure.** As telas recebem `(Modo) -> LivroFormularioViewModel` em vez de `Dependencias`. Elas ficam sem saber como o ViewModel é montado (inversão de dependência), e testes ou capturas injetam qualquer fábrica.

**Folha e ciclo de vida.** Uma `sheet` não faz a tela de trás receber `onAppear` ao fechar. Por isso a releitura do banco foi para o `onDismiss` da sheet.

**`FolhaPendente` e efeito colateral no `body`.** Este foi o aprendizado mais valioso da tarefa; veja "Armadilhas". Em resumo: o SwiftUI chama o bloco do `navigationDestination` (e qualquer `body`) quantas vezes quiser e pode descartar o resultado; esses blocos precisam ser *funções puras do estado*. Efeitos (gastar um pedido, gravar, disparar rede) vão em `onAppear`/`task`/ações.

### Por que assim
- **Regra no Domínio, não no ViewModel:** é lógica pura, testa sem `@MainActor`, e a tela de confirmação da Fase 3 (pós-leitura de código de barras) reaproveita a mesma validação.
- **Texto no rascunho, `Int` ao salvar:** o estado inválido precisa existir para ser apontado.
- **Relê o livro do banco no modo edição:** a mesma fonte única da verdade do detalhe (2.4c); a rota leva só o id.
- **Lista de campos para autores:** não depende do Return e dá identidade clara a cada nome.
- **Exigência só no formulário:** protege a importação da Fase 3.
- **Asterisco no rótulo** (escolha do Ricardo) em vez de "(obrigatório)" no placeholder, que desaparece ao digitar; a nota cinza "* obrigatório" foi tirada por ele, e ficam as mensagens vermelhas.

### Alternativas descartadas
- **`Int?` direto no ViewModel:** perde o "20a".
- **`NumberFormatter`/`Int(...)` puro:** `Int("1.710")` é `nil`; e formatadores dependem de locale (aceitariam vírgula em alguns, rejeitariam ponto em outros). Regra explícita é previsível.
- **Entidade `Autor` no Core Data:** relação muitos-para-muitos, migração e junções para ganho nenhum hoje.
- **Caixa multilinha para autores:** ver acima.
- **Obrigar só o título:** a recomendação inicial; o Ricardo preferiu cadastros mais completos, o que é uma decisão legítima de produto, com o custo conhecido.
- **Validar no banco (Core Data `optional = NO`):** quebraria importação.

### Padrões e boas práticas
- **Draft / DTO de formulário** e **parse na borda**. Não vale para telas triviais (um campo, sem validação): o custo de um tipo extra não compensa.
- **Preservar o que não se edita** ao salvar: "copiar e alterar" (`var novo = base`), nunca reconstruir.
- **Funções puras para regras** e testes de tabela (vários casos de `move`).
- **Closure fábrica** no lugar de passar um contêiner de dependências inteiro (evita *service locator* disfarçado).
- **Testar com o estado vazio, o limite e o absurdo** (overflow, "½", "1..710").

### Armadilhas
- **Bug 1: "Cancelar não fecha e Salvar não funciona".** As capturas abriam o formulário como *raiz* da tela, sem folha por baixo. `dismiss()` só fecha o que foi apresentado; sem apresentação, não faz nada. Salvar gravava no banco, mas a tela ficava parada. Diagnóstico: o Ricardo testou o app que a captura deixou aberto; o código estava certo, o *cenário* estava errado. Moral: ferramenta de teste/captura não pode montar a tela de um jeito que o app real nunca monta.
- **Bug 2: "a edição abre sozinha ao ver qualquer livro".** O booleano `abrirFormulario` era passado a *toda* `LivroDetalheView` criada pelo `navigationDestination`. O mesmo defeito existia em `abrirConfirmacaoDoLivro` desde a 2.4c. Correção: `FolhaPendente`, classe guardada em `@State`, com um alvo (`Estante` ou `RotaDoLivro`); só a tela pedida abre, uma vez.
- **Tropeço dentro da correção.** A 1ª versão "consumia" o pedido dentro do bloco do `navigationDestination`. Nenhuma folha abriu: o SwiftUI chamou o bloco mais de uma vez e descartou a primeira view montada; o pedido foi gasto na descartada. Versão final: `folha(em:)` só *lê*; `esquecer(se:)` roda no `.onAppear` da tela-alvo (a que ficou na tela). Usa `@State` porque quem monta a `NavegacaoView` pode recriá-la, e uma referência `let` nova reiniciaria o pedido.
- **Compilação:** usar `self.rascunho` antes de todas as propriedades estarem inicializadas no `init` é erro em Swift (two-phase initialization: antes de tudo inicializado, `self` não pode ser lido). Calcule num `let inicial` local e atribua às duas propriedades.
- **"DTXProxyChannel" / Testing failed sem nenhum erro de teste:** falha de infraestrutura do simulador, não do código; rodar de novo resolveu. Diagnóstico: ausência de `error:` ou de asserção falha no log.
- **Pendências:** campo preenchido perde o nome (o placeholder some; "1965" sem dizer que é o ano), a tratar no estilo do Formulário; arrastar autor no iOS 16 pode exigir toque longo (Ricardo confere).

### Para ir além
- Alexis King, *Parse, don't validate* (artigo; busque o título).
- Documentação Apple: *Form*, *sheet(isPresented:onDismiss:content:)*, *DismissAction* e *interactiveDismissDisabled(_:)*.
- Documentação Apple, *The Swift Programming Language*: "Initialization" (inicialização em duas fases).

### Perguntas
1. Com suas palavras: por que `RascunhoLivro` guarda o ano como `String` e só vira `Int` em `montar`? O que se perderia com `Int?`?
2. Aplicação: na Fase 3, o Gemini devolve um livro sem editora. A tela de confirmação reaproveita `RascunhoLivro`. O que acontece ao salvar, e por que isso é desejável ou não? O que mudaria se a exigência estivesse em Core Data?
3. Raciocínio: no `onMove`, em `[A,B,C,D]`, o usuário arrasta `A` para depois de `C`. Qual é o `toOffset` recebido e qual a lista final? E por que consumir o pedido da `FolhaPendente` dentro do bloco do `navigationDestination` fez nenhuma folha abrir?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

(sem respostas)

---

## Tarefa 2.4e — Prateleira com sugestões no formulário do livro (2026-10-10)

### O que foi feito
Nova regra pura `SugestaoDePrateleira.sugerir(para:entre:limite:)` em `Dominio/Regras/` (10 testes). O `LivroFormularioViewModel` ganhou `prateleirasDaEstante`, `carregarPrateleiras()`, `sugestoesDePrateleira` e `escolherPrateleira(_:)` (5 testes). Na `LivroFormularioView`, o campo da prateleira ganhou `@FocusState` e, enquanto está em foco, linhas-botão com as etiquetas já usadas na estante. Total: 293 para 308 testes, e o Ricardo testou no simulador.

### Conceitos envolvidos

**Dado livre que precisa de vocabulário controlado.** "Prateleira" é texto livre (não há entidade `Prateleira`). Texto livre produz variantes ("Caixa azul", "caixa azul ", "caixa  azul"), e a tela da estante agrupa por etiqueta. A sugestão é o remédio barato: em vez de normalizar o banco, empurra o usuário a reutilizar a grafia existente na hora da digitação. É o mesmo problema de uma coluna de "tags" sem tabela de domínio.

**Chave de normalização.** `Normalizacao.chave` (minúsculas, sem acento, espaços reduzidos) define quando duas grafias são "a mesma etiqueta". Padrão: **chave canônica** para comparar, **grafia original** para exibir. Aparece em `semGrafiasRepetidas`: ordena, depois usa `Set.insert(...).inserted` para ficar com a primeira grafia de cada chave. `insert` devolve uma tupla `(inserted, memberAfterInsert)`, e `inserted == false` indica que a chave já existia. É um "distinct by" em O(n) após a ordenação.

**Por que há duplicatas se o Core Data faz DISTINCT?** `returnsDistinctResults` compara os valores *crus* da coluna (byte a byte). "caixa azul" e "Caixa azul " são valores diferentes para o banco, então chegam como duas linhas. O DISTINCT do banco e o "mesmo" do domínio são relações de igualdade diferentes. A regra do domínio é quem sabe o que é igual para o usuário.

**Ordem natural: `localizedStandardCompare`.** É a comparação que o Finder usa: números dentro do texto são comparados como números ("2ª" antes de "10ª") e ignora-se parte da diferença de acentuação conforme o locale. Comparação lexicográfica simples poria "10ª" antes de "2ª" (porque "1" < "2").

**Classificação em dois grupos.** Com texto digitado: grupo 1 (a chave *começa* com o digitado: `hasPrefix`), grupo 2 (apenas *contém*). Cada grupo mantém a ordem natural, porque a lista já vem ordenada e `append` preserva a ordem (um particionamento estável feito à mão). Custo total: O(n log n) pela ordenação, com n em dezenas. Nada que justifique índice.

**Instabilidade do `sorted`.** O `sorted` do Swift não garante estabilidade (a documentação não promete; a implementação atual é um timsort, mas não se deve depender disso). Se o comparador empata dois elementos diferentes, a ordem entre eles pode depender da ordem de entrada. Aqui o empate mudaria *qual grafia sobrevive* ao filtro de repetidas, ou seja, o resultado dependeria da ordem em que o banco devolveu as linhas. O desempate `a < b` torna a ordem total e a função determinística. Regra geral: um comparador deve ser uma ordem total estrita; se não for, desempate.

**Foco no SwiftUI.** `@FocusState` é um estado ligado ao foco do teclado; `.focused($editandoPrateleira)` conecta o campo a ele. Atribuir `false` tira o foco e fecha o teclado. Usado para mostrar as sugestões só enquanto se edita, e para fechá-las ao escolher.

**Falha tolerada com `try?`.** `(try? await repositorio.prateleiras(...)) ?? []`. Em geral `try?` engole erros e é suspeito; aqui é deliberado, porque a sugestão é conveniência e um erro de leitura não deve impedir o cadastro. Foi testado (`testFalhaAoLerPrateleirasNaoAtrapalhaOFormulario`) para documentar a intenção.

**`onChange(of:)` na forma de 1 parâmetro.** `.onChange(of: x) { _ in ... }` é a assinatura do iOS 16; a de dois parâmetros ou sem parâmetros é iOS 17 e fica proibida pela regra dos dois Xcodes. O reload dispara com a troca de estante porque as etiquetas pertencem a cada estante.

### Por que assim
- **Regra no Domínio:** pura, testável sem SwiftUI e sem Core Data, e reutilizável (a confirmação pós-código-de-barras da Fase 3 pode usá-la).
- **Normalizar na regra, não no repositório:** a porta continua simples e o conceito de "mesma etiqueta" fica num lugar só, o mesmo de `AgrupamentoPorPrateleira`.
- **Exibir sem o igual ao digitado:** se já digitou "caixa azul", sugerir "caixa azul" é ruído.
- **Limite de 5:** a lista fica dentro de um `Form`, empurrando os campos de baixo; cinco cabem sem rolar.

### Alternativas descartadas
- **Reaproveitar `Tokenizador`/BM25F da busca:** pesado para dezenas de etiquetas; plural e correção de digitação, ótimos para achar livros, confundiriam aqui (digitar "caixa" não deve sugerir "caixas" por heurística).
- **`Picker`/`Menu`:** não permite criar etiqueta nova no mesmo lugar.
- **`.searchSuggestions`:** só existe para `.searchable`, não para `TextField`.
- **Barra sobre o teclado (`inputAccessoryView`):** exige UIKit.
- **Entidade `Prateleira`:** resolveria a duplicação de vez, mas traz relação, migração e telas de gerenciamento; fica como opção se o texto livre incomodar.

### Padrões e boas práticas
- **Chave canônica + grafia de exibição**; **"distinct by"** com `Set`.
- **Degradação graciosa** para recursos auxiliares.
- **Comparador como ordem total.** Quando NÃO usar `try?`: sempre que a falha precise ser vista pelo usuário ou registrada (salvar, apagar).
- **Teste que registra a decisão**: o teste de falha existe para que ninguém "conserte" o `try?` sem saber por que ele está lá.

### Armadilhas
- **O erro instrutivo do teste de empate.** Supus que `localizedStandardCompare` empatasse "Caixa azul" e "caixa azul". Falhou em duas rodadas: (1) " caixa  azul " (espaço duplo interno, só aparado) ganhava por ordenar antes, o que revelou que a grafia exibida também precisava de espaços arrumados (`split` + `joined`); (2) a ordem natural **não** empata maiúsculas: põe a minúscula antes ("caixa azul" < "Caixa azul"). Lição: **não presuma o comportamento de uma comparação localizada; teste-a.** `localizedStandardCompare` ignora algumas diferenças (acentos, em geral) mas a regra exata depende do locale e da ICU; nunca a use para definir igualdade, só ordem. Para igualdade, a chave explícita.
- **Consequência registrada no PLANO:** a sugestão pode mostrar uma grafia diferente do título do grupo na estante, que usa a grafia *mais usada* (`AgrupamentoPorPrateleira`). A porta não devolve contagens, então a sugestão escolhe a primeira em ordem natural. Se incomodar, a evolução é a porta devolver `(etiqueta, quantidade)`.
- **`split(whereSeparator:)` descarta sequências vazias** por padrão (`omittingEmptySubsequences: true`), por isso "  " vira `[]` e `joined` dá "". É o que permite o `filter { !$0.isEmpty }` seguinte.
- **Sugestões só em foco:** se o teste manual no simulador não mostrar a lista, confira se o campo realmente ganhou foco (toque no campo, não só tabulação).
- **Corrida de carregamento:** `carregarPrateleiras()` dispara em `Task` a cada troca de estante; trocas muito rápidas poderiam terminar fora de ordem e deixar as etiquetas da estante errada. Improvável aqui (leitura local rápida), mas é o tipo de coisa a conferir se houver rede no caminho.

### Para ir além
- Documentação Apple: *FocusState* e `localizedStandardCompare(_:)` (NSString).
- Documentação do Swift: `Sequence.sorted(by:)` (critério "strict weak ordering") e `Set.insert(_:)`.
- Unicode Technical Standard #10 (Unicode Collation Algorithm), para entender por que a comparação localizada se comporta assim.

### Perguntas
1. Com suas palavras: por que `returnsDistinctResults` do Core Data não bastou, e o que a `Normalizacao.chave` resolve que o banco não resolve?
2. Aplicação: se você quisesse que a sugestão mostrasse a grafia *mais usada* (como o título do grupo na estante), o que mudaria na porta `prateleiras(naEstante:)` e na regra `sugerir`? Onde ficaria o desempate?
3. Raciocínio: sem o desempate `a < b`, que cenário concreto daria resultados diferentes para os mesmos dados? E por que `localizedStandardCompare` não serve para decidir se duas etiquetas são "a mesma"?

### Minhas respostas
(sem respostas)

## Tarefa 2.4 / Estilo 0a — Referências e direção visual (2026-10-12)

### O que foi feito
Sessão de decisão (sem código Swift) que fixou a direção visual do app antes de estilizar as telas: referências e o papel de cada uma, paleta por papel com contraste medido, tipografia, forma e movimento, posição sobre o Liquid Glass e paleta de categorias. Tudo registrado em `docs/PLANO.md` (Histórico de decisões de 12/10) e na linha de status do `CLAUDE.md`. Próximo passo: Estilo 0b, os tokens em `Apresentacao/Componentes/`.

### Conceitos envolvidos

**Referências com papéis separados.** Em vez de "copiar um app", cada referência responde a uma pergunta distinta de design:

| Referência | O que emprestamos |
| --- | --- |
| Apple Books | Disposição: capas protagonistas, títulos em serifa (New York), transição capa para detalhe |
| Bevel | Forma e movimento: cartões macios, cantos arredondados, sem divisórias, animações por mola |
| Goodreads | Densidade de informação (útil à tela de Detalhe; a estética foi descartada por ser pesada) |
| Shelf Life | Simplicidade: prateleiras por estado, sem conta |

Observação honesta registrada na sessão: as páginas de Shelf Life e Bevel não descreviam o visual; essas leituras vieram do conhecimento geral dos apps, não de fonte verificada. Vale conferir olhando os apps.

**Regra 60-30-10.** 60% da área é fundo, 30% é superfície (cartões, seleção), 10% é destaque. Um destaque só: quando tudo chama atenção, nada chama. Cores são escolhidas por *papel* (fundo, superfície, destaque), não por "gosto".

**Contraste WCAG.** Luminância relativa L de cada cor (cada canal sRGB é linearizado e ponderado: L = 0,2126 R + 0,7152 G + 0,0722 B). Razão = (L1 + 0,05) / (L2 + 0,05), com L1 a mais clara. Mínimo para texto normal: 4,5:1 (AA). O 0,05 evita divisão por zero no preto e modela a luz ambiente. Resultados medidos:

| Par | Contraste | Veredito |
| --- | --- | --- |
| #AED3FC (azul claro) × branco | 1,55 | reprova: nunca texto/ícone sobre branco |
| petróleo #1F5F73 × branco | 7,14 | passa |
| petróleo #1F5F73 × #AED3FC | 4,60 | passa |
| petróleo #1F5F73 × #1C1C1E (fundo escuro) | 2,38 | reprova |
| #AED3FC × #1C1C1E | 10,96 | passa |
| #0E4C5A × branco / × azul claro | 9,55 / 6,15 | passa (alternativa) |
| #2A6F85 × branco / × azul claro | 5,66 / 3,64 | reprova sobre azul claro |

Consequência importante: **no modo escuro os papéis trocam.** O petróleo, ótimo no claro, some no fundo escuro (2,38); então o azul claro vira destaque (10,96) e o petróleo vira superfície (texto branco sobre ele: 7,1). O "tom escuro" de uma cor não é "a mesma cor mais escura": é a cor que cumpre o mesmo papel com contraste suficiente.

**Tipografia.** SF (fonte do sistema) na interface; New York (`Font.system(..., design: .serif)`, disponível no iOS 16) só em títulos de livros e estantes, onde carrega a identidade de "livro". Tudo com Dynamic Type (tamanhos relativos às preferências do usuário) para acessibilidade.

**Cantos contínuos ("squircle").** `RoundedRectangle(cornerRadius:style: .continuous)` usa uma curva de transição gradual entre a reta e o arco (curvatura contínua), em vez de um quarto de círculo preso à reta. Visualmente é mais suave e é o que o iOS usa nos ícones. Raios escolhidos: 8, 12 e 20.

**Elevação sem contorno.** Sem linhas de contorno: a separação vem de cor e sombra leve. No escuro a sombra quase não aparece (sombra preta sobre quase preto), então a elevação passa a ser por cor: superfícies mais elevadas ficam mais claras.

**Animação por mola.** Em vez de curva com duração fixa, a mola (`Animation.spring`) simula massa e rigidez, e responde bem a interrupções (o toque pode mudar de ideia no meio). Tokens nomeados evitam números espalhados. Respeitar "Reduzir movimento" via `@Environment(\.accessibilityReduceMotion)`: quem ativa isso não deve ver deslocamentos grandes.

**Liquid Glass e compilação condicional.** Liquid Glass é a linguagem visual do iOS 26; as APIs `.glassEffect()`, `GlassEffectContainer` e `.buttonStyle(.glass/.glassProminent)` são só iOS 26. A lição central:

```mermaid
flowchart LR
  A[Código usa API do iOS 26] --> B{Compila no Xcode 14.2?}
  B -- "não: SDK desconhece o símbolo" --> C["if #available não ajuda"]
  C --> D["#if compiler(>=6.2) ajuda, mas só vale no .ipa da CI"]
  D --> E[Impossível ver no simulador iOS 16 local]
```

`#available` é checagem em **tempo de execução**: o código dentro do `if` ainda precisa **compilar**, e o compilador do Xcode 14.2 não conhece o símbolo, então dá erro. `#if compiler(>=6.2)` é **compilação condicional**: o trecho nem é analisado em compiladores antigos. Mas aí o efeito existiria só no binário da CI, sem como ser visto aqui. (Do conhecimento geral, não confirmado na pesquisa: app compilado com o SDK do iOS 26 ganha o vidro nas barras do sistema ao rodar no iOS 26.)

**Paleta de categorias.** Cores do sistema da Apple (HIG), medidas como texto sobre branco e como chip pastel (cor a 20% sobre branco, texto #1C1C1E):

| Cor | texto × branco | chip pastel × texto escuro |
| --- | --- | --- |
| red FF3B30 | 3,55 | 13,00 |
| orange FF9500 | 2,20 | 14,50 |
| yellow FFCC00 | 1,51 | 15,54 |
| green 34C759 | 2,22 | 14,47 |
| mint 00C7BE | 2,12 | 14,41 |
| teal 30B0C7 | 2,57 | 14,19 |
| cyan 32ADE6 | 2,54 | 14,25 |
| blue 007AFF | 4,02 | 13,05 |
| indigo 5856D6 | 5,65 | 12,79 |
| purple AF52DE | 4,13 | 13,18 |
| pink FF2D55 | 3,65 | 12,81 |
| brown A2845E | 3,50 | 13,73 |

Leitura: como **texto**, só o índigo passa (4,5); como **fundo pastel com texto padrão**, todas passam com folga. Daí o desenho: chip com fundo a ~20% e texto na cor padrão, cor cheia apenas num pontinho. Nota: o chip pastel sobre branco tem só ~1,2:1 contra o fundo; quem o distingue é a forma, não o contraste, o que é aceitável porque o chip não carrega informação *só* pela cor (tem texto).

### Por que assim
- **Um destaque só (petróleo):** coerência e hierarquia; o que é tocável se reconhece de longe.
- **Contraste medido, não "no olho":** a decisão sobre papéis no escuro só aparece quando se calcula; olho engana (o azul claro "parece" legível sobre branco e dá 1,55).
- **Serifa só em títulos de livros/estantes:** a serifa sinaliza "isto é um livro"; usada em tudo, perde esse significado.
- **Vidro imitado só nos flutuantes** (botão da câmera, barra de filtros): `.ultraThinMaterial` + brilho fino na borda + pressão por mola (`ButtonStyle` com `configuration.isPressed`). Material translúcido sobre listas prejudica a leitura; em elementos que flutuam acima do conteúdo, ele faz sentido.
- **Cores do sistema sem azul/ciano/teal:** esses tons se confundiriam com o destaque e com o que é tocável. Sobram cerca de 9 cores.

### Alternativas descartadas
- **"Só SF"** (sem identidade) e **serifa também nos títulos de tela** (cansa, dilui o papel da serifa).
- **Liquid Glass real via `#if compiler(>=6.2)`:** não verificável localmente; arriscaria divergência entre o que o Ricardo vê e o que a CI gera.
- **Vidro em tudo:** perde legibilidade sobre listas.
- **Plotly Pastel para categorias:** hex fixos, sem variante para modo escuro, enquanto as cores do sistema se adaptam.
- **Modo escuro removido:** mantido (decidido em 10/10).
- Padrões de HIG (por exemplo, usar mola, transições) ficaram fora do Histórico por não serem surpreendentes.

### Padrões e boas práticas
- **Tokens de design** (cor, tipografia, raio, animação com nomes por papel): mudar o visual vira mudar um lugar. Quando NÃO usar: protótipo descartável de uma tela só.
- **Cor nunca como único canal de informação** (acessibilidade para daltonismo): o chip tem texto.
- **Cores semânticas por papel**, com variante clara e escura via asset catalog.
- **Decisão registrada com o motivo** no PLANO, para não ser reaberta sem argumento.

### Armadilhas
- **Confundir `#available` com `#if`:** o primeiro é execução, o segundo é compilação. Sintoma: "Cannot find 'glassEffect' in scope" no Xcode 14.2 mesmo dentro de `if #available(iOS 26, *)`.
- **Adaptar cor ao escuro escurecendo:** o petróleo escurecido falha (2,38). Meça sempre os dois modos.
- **Sombra no modo escuro:** quase invisível; a elevação precisa vir da cor.
- **Fonte serifa sem Dynamic Type:** `Font.system(size:design:)` com tamanho fixo ignora a preferência do usuário; prefira `Font.system(.title, design: .serif)` (estilo de texto) ou `relativeTo`. Verifique na documentação a variante disponível no iOS 16.
- **Cálculos de contraste sobre cores com transparência:** o chip a 20% precisa ser composto sobre o fundo real antes de medir (e muda entre claro e escuro).

### Para ir além
- Apple, *Human Interface Guidelines*: Color, Typography e Accessibility (contraste).
- W3C, *WCAG 2.x*, critério 1.4.3 (Contrast Minimum) e a definição de luminância relativa.
- Documentação Apple de `RoundedRectangle` / `RoundedCornerStyle.continuous` e de `accessibilityReduceMotion`.

### Perguntas
1. Com suas palavras: por que `if #available(iOS 26, *)` não permite usar `.glassEffect()` no Xcode 14.2, e o que `#if compiler(>=6.2)` muda? Por que, mesmo assim, ele foi descartado?
2. Aplicação: se você trocasse o destaque do app para #2A6F85, em quais pares de superfície ele deixaria de ser seguro para texto, e que valor de contraste você usaria para decidir? Calcule o que puder à mão.
3. Raciocínio: por que, no modo escuro, o petróleo vira superfície em vez de continuar destaque, e por que "chip pastel com texto escuro" funciona para as 12 cores do sistema enquanto "texto colorido sobre branco" quase nunca funciona?

### Minhas respostas
(sem respostas)

---

## Tarefa 2.4 / Estilo 0b-c — Tokens de estilo, testes de contraste e catálogo (2026-10-12)

### O que foi feito
Os fundamentos visuais viraram código em `ios/Estantes/Apresentacao/Componentes/`: `Cor.swift` (paleta clara/escura), `Estilo.swift` (espaço, raio, fonte, animação, sombra), `EstiloVidro.swift` e `EstiloPrincipal.swift` (estilos de botão). Os contrastes são testados em `EstantesTests/Apresentacao/` (`Contraste.swift`, `ContrasteTests.swift`, `PaletaTests.swift`). Um catálogo só de DEBUG (`App/CatalogoDeEstilo.swift`) mostra tudo no simulador e foi o instrumento que revisou a paleta e desenhou o chip de categoria. Commits 611bc32, d1d8b6f e 79261b3; 318 testes (2 pulados).

### Conceitos envolvidos

**1. Cor dinâmica em código.** `UIColor { traits in ... }` cria uma cor cujo valor é decidido *na hora de desenhar*, a partir do `UITraitCollection` do contexto (claro/escuro, contraste). `Paleta` usa `UIColor(claro:escuro:)` e `Cor` embrulha com `Color(uiColor:)`. Em vez de asset catalog, o hex fica visível no diff e o teste consegue resolver cada modo: `cor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))` devolve uma cor fixa que se pode medir.

**2. Papéis finais da paleta.**

| Papel | Claro | Escuro |
| --- | --- | --- |
| fundo | FFFFFF | 000000 |
| cartao | FFFFFF (+ sombra) | 1C1C1E |
| superficie | AED3FC | 12305A |
| destaque | 0A5FD6 | AED3FC |
| sobreDestaque (rótulo sobre o destaque) | FFFFFF | 1C1C1E |
| textoSecundario | 4A5A62 | C9D6DC |
| texto principal | `.primary` do sistema | idem |

O princípio da entrada anterior se confirma: no escuro, os papéis não são "a mesma cor escurecida", são a cor que cumpre o papel com contraste suficiente (destaque vira o azul claro; superfície vira o marinho).

**3. Contraste WCAG por dentro.** Passos: (a) converter cada canal sRGB de 0–1 para linear (`c <= 0,03928 ? c/12,92 : ((c+0,055)/1,055)^2,4`), porque a luz física soma de forma linear, mas o valor gravado é curvado por gama; (b) L = 0,2126 R + 0,7152 G + 0,0722 B (o olho é muito mais sensível ao verde); (c) razão = (L_claro + 0,05)/(L_escuro + 0,05). Verificação do próprio cálculo com valores de fonte externa: preto × branco = 21 e #777777 × branco = 4,48 (WebAIM). Esse é o jeito certo de validar uma função de teste: contra um número que você não calculou com ela.

**4. Por que o teste mora no alvo de testes.** O app nunca calcula contraste; só os testes precisam. Pôr a função no app seria código de produção sem uso (mesmo precedente do MRR em 09/10). E `guard getRed(...) else { preconditionFailure }`: `UIColor.getRed(_:green:blue:alpha:)` devolve `false` se a cor não está num espaço RGB (ex.: cor de padrão) e deixa as variáveis como estavam (zeradas). Sem o guard, o teste mediria "preto" calado e poderia passar ou falhar pelo motivo errado. Falhar alto é melhor que medir errado.

**5. Os três limiares usados em `PaletaTests`.**

| Uso | Mínimo | Critério WCAG |
| --- | --- | --- |
| texto normal | 4,5:1 | 1.4.3 |
| elemento não-texto (ícone, forma de controle) | 3,0:1 | 1.4.11 |
| sobreDestaque × destaque (rótulo de botão) | 4,5:1 | 1.4.3 |

Daí a regra: sobre a superfície clara (#AED3FC), texto é `.primary` (13,5:1) e o destaque só aparece como ícone ou forma (≥3:1).

**6. O `.secondary` do sistema reprova.** É `rgba(60,60,67,0.6)`: uma cor *com transparência*, então o resultado depende do que está atrás. Sobre branco dá ≈3,44:1; sobre #AED3FC, 2,88. Isso só apareceu porque o teste existia. Virou token próprio, opaco:

| textoSecundario | × fundo | × cartão | × superfície |
| --- | --- | --- | --- |
| claro #4A5A62 | 7,17 (branco) | 7,17 | 4,62 (#AED3FC) |
| escuro #C9D6DC | 14,14 (preto) | 11,45 (#1C1C1E) | 8,86 (marinho) |

**7. Mutação de prova.** Para saber se um teste de verdade pega o defeito, estrague o código de propósito: trocar textoSecundario claro por #8A8A8E fez o teste falhar com 3,44 e 2,21, exatamente os números calculados à parte em Python. E ao trocar o destaque para #0A5FD6 o teste ficou vermelho com 3,73 (sobre a superfície) até a regra de 3:1 para ícones ser escrita. Vermelho → verde nas duas fronteiras (`Contraste.razao` e a paleta).

**8. Medição dos azuis candidatos.**

| Azul | × branco | × #AED3FC |
| --- | --- | --- |
| petróleo 1F5F73 | 7,14 | 4,60 |
| sistema 007AFF | 4,02 (reprova) | 2,59 |
| 0A5FD6 | 5,80 | 3,73 |
| 2563EB | 5,17 | 3,33 |
| 0369A1 | 5,93 | 3,82 |

Lição: dois tons claros juntos nunca dão contraste de texto. Nenhum azul vibrante passa 4,5 sobre o azul claro. Em vez de buscar a cor mágica, mudou-se a regra de uso. Escolheu-se #0A5FD6 *olhando* quatro candidatos no catálogo (com um seletor temporário `-azul` só em DEBUG, removido depois). O número elimina; o olho escolhe entre os que sobraram.

**9. Tokens de forma, espaço e movimento.**
- `Espaco` 4/8/12/16/24/32 e `Raio` 8/12/20; `.cantos()` aplica `RoundedRectangle(cornerRadius:style: .continuous)`.
- `Fonte`: só serifadas, e `Font.system(.title2, design: .serif).weight(.semibold)` compilou no Xcode 14.2. Isso responde a dúvida da entrada anterior: o estilo de texto semântico mantém o Dynamic Type, ao contrário de `Font.system(size:design:)`.
- `Animacao`: suave (spring 0,35/0,85), rapida (0,25/0,9), esmaecer (easeInOut 0,2). `Animacao.escolher(_:reduzirMovimento:)` concentra a regra do "Reduzir movimento" num lugar só (dissolver em vez de deslocar), em uma função pura que dá para testar. `.animacaoSuave(valor:)` é o modificador de uso.
- `.sombraSuave()`: 8% preto, raio 12, y 4 no claro; nada no escuro (elevação por cor). Um `ViewModifier` que lê `colorScheme` do ambiente decide.

**10. `ButtonStyle` não é `View`.** `EstiloVidro` e `EstiloPrincipal` implementam `makeBody(configuration:)`, mas `@Environment` só funciona dentro de uma `View`. Padrão usado: `makeBody` devolve uma `View` privada pequena que lê `@Environment(\.isEnabled)` e `configuration.isPressed`. `EstiloVidro` imita o Liquid Glass: `ultraThinMaterial`, borda de 0,5 pt em gradiente branco, e ao pressionar escala 96% + véu do destaque a 15%. `EstiloPrincipal`: fundo destaque, rótulo sobreDestaque, brilho −0,08 e escala 97% ao pressionar, opacidade 0,4 desabilitado.

**11. `.tint` na raiz.** `.tint(Cor.destaque)` em `RaizView` se propaga pelo ambiente a toda a hierarquia (conferido na captura do formulário). É a mesma ideia de herança de ambiente do `@Environment`: definir uma vez no topo, ler nas folhas.

**12. O catálogo como instrumento.** São três páginas (`-captura Estilo`, `EstiloTelas`, `EstiloCategorias`) porque o `simctl` não rola a tela. Para variar o contexto sem tocar no código: modo escuro com `xcrun simctl ui booted appearance dark`; texto grande com o argumento de lançamento `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL` (o simctl do Xcode 14.2 não tem opção de tamanho de texto). Revelou dois defeitos que nenhuma tabela mostrava:
- `.borderedProminent` pinta o rótulo sempre de branco, ilegível sobre #AED3FC no escuro. Virou `EstiloPrincipal`, que usa o token certo.
- Ícone azul sobre o vidro sumia: o material acompanha o modo (claro/escuro), não a cor da capa por trás; então o ícone passou a `.primary`.
- Com texto grande, chips lado a lado quebram letra a letra (pendência registrada para a composição na 2.5).

**13. Chip de categoria: o problema e a solução.** Desenho do Ricardo: etiqueta `tag` (como releases do GitHub), texto e contorno na cor, fundo branco. Medição das cores do sistema:

| Cor | padrão × branco | alto contraste × branco | escuro × 1C1C1E |
| --- | --- | --- | --- |
| red | 3,55 | 5,38 | 4,99 |
| orange | 2,20 | 5,28 | 8,28 |
| yellow | 1,51 | 5,20 | 12,05 |
| green | 2,22 | 4,40 | 8,42 |
| mint | 2,12 | 4,73 | 11,30 |
| indigo | 5,65 | 9,65 | 3,36 |
| purple | 4,13 | 6,04 | 4,83 |
| pink | 3,65 | 5,35 | 4,83 |
| brown | 3,50 | 5,45 | 5,53 |

A variante de alto contraste do sistema (obtida com `resolvedColor(with: UITraitCollection(traitsFrom: [traços, UITraitCollection(accessibilityContrast: .high)]))`) passa, mas perde a identidade (amarelo vira ocre). Há um limite físico: um amarelo legível sobre branco *não parece amarelo*. Solução "A": dividir o trabalho. O fundo pastel (cor a 15%) e o contorno vivo guardam a identidade, pois são decoração, não texto. O texto usa o mesmo matiz escurecido em HLS só até ~4,6:1 sobre o pastel (red CE0B00, orange 9E5C00, yellow 876C00, green 207C38, mint 007873, indigo 5654D6, purple 9D2BD7, brown 7D6648). No escuro, alto contraste sobre véu. Rosa próprio #FF2D92 (matiz 331°; texto claro CB0062 a 4,62; escuro FF7AC0 a 5,54 sobre o véu), porque o systemPink (349°) ficava a 14° do vermelho (3°) e se confundia com "Constitucional". Em HLS (matiz, luminosidade, saturação), escurecer mexe só na luminosidade e preserva o matiz, e é por isso que a cor continua reconhecível.

### Por que assim
- **Tokens em código, não em asset catalog:** hex no diff, testável por resolução de trait, sem arquivo binário/JSON extra.
- **Testar contraste com valores independentes:** o esperado vem de WebAIM e de Python, não da mesma fórmula do código; senão o teste seria tautológico.
- **Cor própria para textoSecundario:** o `.secondary` transparente não tem contraste definido, depende do fundo.
- **Catálogo antes das telas:** é mais barato errar num catálogo de 3 páginas do que em 6 telas.
- **Chip dividido (decoração vs texto):** respeita o 4,5:1 sem renunciar à identidade por cor, e o texto continua sendo o canal de informação.
- **Linhas novas no Histórico de 12/10 do PLANO:** destaque #0A5FD6 + superfície escura #12305A (revisa a paleta com petróleo) e chip A (revisa a das categorias pastel). Reabrir uma decisão registrada, com o motivo escrito, é o processo certo.

### Alternativas descartadas
- **Petróleo como destaque:** o Ricardo achou "opaco, triste"; passava em contraste, mas contraste não é tudo.
- **Azul do sistema 007AFF:** 4,02 sobre branco.
- **Chip B (fundo branco, etiqueta preenchida, texto preto):** perde o texto na cor.
- **Alto contraste puro:** passa, mas perde o pastel.
- **Asset catalog para as cores:** ver acima.
- **Seletor `-azul` permanente:** era ferramenta de decisão, removida depois.
- **Adiados com nota** (revisão em dois eixos): lista de pares do teste à mão (a vigilância é manual), modificador de pressão compartilhado no 3º estilo de botão, e promover cartão/chip a componentes no estilo do Inicio.

### Padrões e boas práticas
- **Fonte única da verdade para regras transversais** (`Animacao.escolher` para Reduzir movimento): quando NÃO usar: regra usada uma vez só.
- **Falhar alto** (`preconditionFailure`) em código de teste que pode medir a coisa errada em silêncio.
- **Mutação de prova:** estragar o código de propósito para ver o teste falhar; prova de que o teste protege algo.
- **Revisão em dois eixos** (padrões × plano) rodou duas vezes; os achados aplicados foram, entre outros, P1 (tint/borderedProminent), P3 (`Animacao.escolher`), P4 (`guard getRed`) e pendências explícitas no PLANO.
- **Medir e olhar:** número elimina candidatos; o olho escolhe entre os restantes.

### Armadilhas
- **Cores com alfa** (`.secondary`, véus): o contraste depende do que está atrás; componha antes de medir.
- **Estilos prontos do sistema** (`.borderedProminent`) fixam cor do rótulo e ignoram seus tokens; veja no modo escuro.
- **`getRed` devolvendo `false`:** valores ficam zerados sem erro.
- **Material translúcido:** acompanha o modo, não o conteúdo atrás; ícone colorido pode sumir.
- **Dynamic Type grande:** layouts lado a lado quebram; teste com AccessibilityL.
- **Tela que "ainda não usa os tokens":** o cinza que o Ricardo reclamou era `secondarySystemBackground` dos cartões da 2.4 e do `Form`, não a paleta nova. Antes de culpar o token, confirme quem pinta o pixel.

### Para ir além
- W3C, *Understanding WCAG 2.x*: critérios 1.4.3 (Contrast Minimum) e 1.4.11 (Non-text Contrast), com a fórmula de luminância relativa.
- Apple, documentação de `UIColor.init(dynamicProvider:)`, `UITraitCollection` e do protocolo `ButtonStyle`.
- Apple, *Human Interface Guidelines*: Color e Accessibility.

### Perguntas
1. Com suas palavras: por que um `ButtonStyle` precisa devolver uma `View` privada para ler `@Environment`, e o que a "mutação de prova" demonstrou sobre o teste de contraste?
2. Aplicação: se o app passasse a ter uma superfície vermelha FF3B30 com texto `.primary` claro (preto-ish), o que você mediria e com qual limiar? E se o texto fosse o `destaque` #0A5FD6?
3. Raciocínio: por que o chip pastel de "amarelo" não pode ter o texto no mesmo amarelo e continuar parecendo amarelo? Qual é a divisão de trabalho da solução A entre fundo, contorno e texto?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

(sem respostas)

---

## Tarefa 2.4 — Estilo da tela Inicio (2026-10-12)

### O que foi feito
Primeira tela do estilo "tela por tela", depois do Estilo 0. `InicioView.swift` passou a usar os tokens; o cartão e a ilustração do vazio viraram componentes em `Apresentacao/Componentes/CartaoDeEstante.swift` (`CartaoDeEstante`, `EstiloCartao`, `IlustracaoEstanteVazia`), que o catálogo DEBUG (`App/CatalogoDeEstilo.swift`) reaproveita em vez de manter uma cópia. `Estilo.swift` ganhou `.pressao(_:)` e `AnyTransition.entrada(reduzirMovimento:)`. A cor de destaque do claro mudou de `#0A5FD6` para `#0579B8` (`Cor.swift`). Três commits (7279017, fa5bacb, c73f4fa); 318 testes passam.

### Conceitos envolvidos

**1. Regra 60-30-10 e hierarquia de superfícies.** Fundo ~60%, superfície ~30%, destaque ~10%. Por isso o cartão é branco (`Cor.cartao`) com `.sombraSuave()`, e não azul na `superficie`: uma grade de cartões todos azuis tomaria a tela inteira e o "30" viraria "90". A sombra, além de separar do fundo, sinaliza "isto é tocável". No escuro a sombra não aparece no preto, então a separação vem da cor (`#1C1C1E`).

**2. Dynamic Type e layout adaptativo.** Duas colunas por padrão, uma quando `dynamicTypeSize.isAccessibilitySize`. Motivo: com texto grande, "Escritório" quebrava letra a letra. Descartados:
- `GridItem(.adaptive(minimum:))`: decide o número de colunas pela *largura disponível*, não pelo tamanho do texto; num iPhone largo ainda caberiam duas colunas com texto enorme.
- `minimumScaleFactor`: encolhe a fonte para caber, o que desfaz exatamente o que o usuário pediu ao aumentar o texto.
A regra (qual tamanho vira uma coluna) é decisão de apresentação, por isso fica na View e não no Domínio.

**3. Alinhamento por `Spacer` e altura mínima.** Dentro de um `VStack`, `Spacer(minLength:)` empurra nome e contagem para a base, de modo que os cartões da mesma linha ficam alinhados mesmo quando um nome ocupa duas linhas. `minHeight: 96` (antes 110, que deixava um vão grande no cartão de 1 livro); com texto grande o conteúdo passa de 96 e o cartão cresce sozinho.

**4. Extração de modificador reutilizável.** O terceiro estilo de botão (`EstiloCartao`) disparou a extração que o PLANO já previa: `.pressao(_:)`, um `ViewModifier` privado que lê `@Environment(\.accessibilityReduceMotion)`, escala 0,97 e anima com a mola `rapida`. A regra prática é "três usos, extrai" (duas repetições ainda são tolerável; antes disso a abstração é palpite). Efeito colateral deliberado: escala única 0,97, enquanto o vidro usava 0,96. Consistência vale mais que a diferença imperceptível.

**5. "Reduzir movimento" precisa de um sinal estático.** Se a única pista de pressão é o encolhimento, quem ativou "Reduzir movimento" fica sem feedback (achado E3). Solução: um véu do `destaque` a 8% sobre o cartão. Véu e não escurecer, porque `#1C1C1E` no modo escuro mal escurece (já está quase preto).

**6. Transições do SwiftUI: fato aprendido na revisão.** `.transition` só roda na view que é *inserida ou removida diretamente* pelo `if`/`switch`/`ForEach`. Quando a lista inteira entra (o `ScrollView` com a `transition`), os cartões filhos não repetem a própria transição; ela só vale quando se cria ou apaga uma estante individual. Por isso não existe transição dupla (P2 descartado). A entrada é mola `suave` (esmaecer + subir 8 pt; só esmaecer com "Reduzir movimento", porque deslocar é movimento), centralizada em `AnyTransition.entrada(reduzirMovimento:)` para não duplicar a regra. Sem cascata: a lista recarrega a cada volta da estante e uma cascata repetida cansaria.

**7. Estado vazio segundo a HIG.** O padrão da Apple (o mesmo do `ContentUnavailableView`, iOS 17+, que aqui não podemos usar): imagem que só informa, título, frase curta e no máximo uma ação. O Ricardo contou três botões de adicionar ao mesmo tempo ("+" da barra, "+" em círculo na ilustração, "Criar a primeira estante"). Um "+" em círculo azul *tem forma de botão do iOS*, então confunde mesmo sendo desenho. Variantes capturadas:

| Variante | Ilustração | Botão central | "+" da barra | Ações |
| --- | --- | --- | --- | --- |
| A | sem "+" | sim | fica | 2 |
| B (escolhida) | sem "+" | sim | some sem estantes | 1 |
| C (estilo Notas) | sem "+" | não (frase "Toque em +…") | só ele | 1 |

Na revisão, o "+" passou a aparecer só em `.pronto` (antes piscava no carregamento e aparecia no erro). O `if temEstantes` ficou *fora* do `ToolbarItem`: dentro, sobraria um item vazio na barra (no iOS 26, uma bolha de vidro sem nada).

**8. Cor, percepção e o critério que decide.** O Ricardo achou o `#0369A1` "amarelado". Medição de pixels: o fundo era `#FFFFFF` puro nas duas capturas. Hipóteses: a capa clara de exemplo `#F2E8D1` ao lado e o *contraste simultâneo* (um azul puxado para o ciano, matiz 201° contra 215° do `#0A5FD6`, faz o branco vizinho parecer mais quente). Mas o critério que decidiu foi funcional: na barra de busca (2.7), os chips de filtro (destaque no ícone, sobre a superfície) convivem com os de categoria, então o destaque precisa ficar longe de todas as cores de categoria. Distâncias em ΔE76 (fórmula simples, imprecisa nos azuis: vale a ordem, não os números):

| Cor da categoria | vs #0A5FD6 | vs #0369A1 |
| --- | --- | --- |
| Índigo (Trabalho) texto #5654D6 | ΔE 14 (26° de matiz) | ΔE 52 |
| Menta (Tributário) texto #007873 | ΔE 82 | ΔE 41 |
| Roxo (Administrativo) | ΔE 46 | ΔE 80 |
| Verde (Processo) | ΔE 117 | ΔE 77 |
| Petróleo #1F5F73 (descartado) | ΔE 62 | ΔE 23 |
| Superfície #AED3FC | 3° de matiz | 10° de matiz |

O contraste WCAG não desempatava (5,80 × 5,93 no branco; 3,73 × 3,82 como ícone na superfície). Alternativa descartada: manter `#0A5FD6` e tirar o índigo das categorias. Moral: dois critérios (legibilidade e distinguibilidade) e só um deles estava no teste automático.

**9. OKLCH: gerar degraus de um mesmo matiz.** OKLab/OKLCH é um espaço perceptualmente mais uniforme que o HSL: L (luz), C (croma) e H (matiz) são eixos separados, então dá para subir a luz mantendo o matiz do `#0369A1`. Fixou-se o matiz e subiram-se L e C em 4 degraus. O teto vem do piso de 3:1 do ícone sobre `#AED3FC`: como `#AED3FC` sobre branco é só 1,55:1, o destaque precisa de ≥ ~4,7:1 no branco para o ícone chegar a 3:1 sobre a superfície. O croma quase não sobe porque o `#0369A1` já está perto do limite do gamut sRGB nesse matiz; o que muda é a luz. Distância entre degraus ≈ 1–1,5 em OKLab (perto do limite do perceptível).

| Tom | Hex | Branco (≥4,5) | Ícone sobre #AED3FC (≥3,0) |
| --- | --- | --- | --- |
| base | #0369A1 | 5,93 | 3,82 |
| t1 | #026DA8 | 5,59 | 3,60 |
| t2 | #0471AC | 5,30 | 3,41 |
| t3 | #0476B4 | 4,93 | 3,18 |
| t4 | #0579B8 | 4,74 | 3,05 (no piso) |
| original | #0A5FD6 | 5,80 | 3,73 |

Distância ao índigo em OKLab: `#0A5FD6` = 6, `#0579B8` = 12. Escolhido t4. O modo escuro (destaque `#AED3FC`, superfície `#12305A`) ficou como estava por escolha do Ricardo (ΔE 63 do índigo escuro, 34 da menta escura; 13,5:1 no preto).

### Por que assim
- **Componentes recebendo só textos** (`nome`, `detalhe`): o catálogo mostra o componente real sem precisar de um `Estante`. É o princípio de depender do mínimo necessário (a View do componente não conhece o modelo).
- **Adaptador inline** (P11) em vez de função extra para transformar `EstanteResumo` em textos: usado num lugar só.
- **Escala única e transição centralizada:** a regra do "Reduzir movimento" e os números mágicos ficam em `Estilo.swift`, ao lado de `Animacao.escolher`.
- **Destaque mais claro e mais ciano** (`#0579B8`): ganha distância do índigo (6 → 12 em OKLab) pagando contraste (5,80 → 4,74, ainda ≥4,5) e ficando no piso do ícone (3,05). Margem pequena, por isso o comentário em `Cor.swift` avisa que é "o mais claro do matiz que ainda passa" e os testes de `PaletaTests` protegem o piso.
- **Registro no PLANO:** linha nova no Histórico revisando a de 12/10 (`#0A5FD6`), porque decisão registrada só se reabre por escrito.

### Alternativas descartadas
- Cartão na `superficie`: encheria a tela de azul.
- `GridItem(.adaptive)` e `minimumScaleFactor`: ver conceito 2.
- Cascata de entrada: cansa quando a lista recarrega.
- Escurecer o cartão pressionado: não funciona no escuro.
- Variantes A e C do vazio: A mantém duas ações; C esconde a ação principal na barra (menos descobrível para quem abre o app pela primeira vez).
- Manter `#0A5FD6` e remover o índigo: troca um problema de paleta de categorias por outro.
- Petróleo como destaque (já descartado antes, ΔE 23 da menta).

### Padrões e boas práticas
- **Rule of three:** extrair abstração no terceiro uso, não no segundo. Quando NÃO: se os usos divergem de verdade (aqui divergiam só em 0,96 × 0,97, sem importância).
- **Um só caminho para a mesma regra** (`entrada(reduzirMovimento:)`, `pressao`, `Animacao.escolher`).
- **Estado de UI como enum** (`carregando/vazio/pronto/erro`) e a barra reagindo a ele (`temEstantes`).
- **Decidir com amostras lado a lado** (variantes A/B/C, degraus t1–t4): comparar no simulador, não na cabeça.
- **Revisão em dois eixos**, aprovada por número (P1/E1, P3, P4, P6, P8, P10, P11, P12, E3, E4/E5); descartes justificados (P2, P5, P7, P9, E2).
- P9: a regra de colunas é Apresentação, não Domínio (Domínio não sabe o que é Dynamic Type).

### Armadilhas
- **`if` dentro do `ToolbarItem`** deixa um item vazio (bolha vazia no iOS 26). Coloque o `if` por fora.
- **`.transition` não é herdada pelos filhos** de uma view inserida: teste o caso de inserir e o de a lista inteira aparecer.
- **ΔE76 é imprecisa nos azuis**: use para ordenar, não para fixar limites (CIEDE2000 ou OKLab são melhores).
- **Percepção ≠ pixel:** o "amarelado" não estava no fundo (medido `#FFFFFF`); o contexto de cores vizinhas muda o que se vê. Meça antes de culpar.
- **Processo (erros reais desta sessão):** duas vezes a captura clara foi sobrescrita pela escura porque o nome do arquivo era o mesmo antes do `mv`: dê nome único já na captura. E um laço `for t in "..."; do set -- $t` falhou no zsh, que, ao contrário do bash, não separa palavras de `$t` sem aspas (sem word splitting por padrão); resolveu-se rodando o laço em `bash -c`. Dica: em scripts, declare o interpretador (`#!/bin/bash`) ou use arrays.

### Para ir além
- Apple, *Human Interface Guidelines*: Empty states / Loading e Accessibility (Dynamic Type, Reduce Motion).
- Björn Ottosson, "A perceptual color space for image processing" (OKLab), em bottosson.github.io.
- Documentação do SwiftUI sobre `AnyTransition` e `ToolbarContentBuilder`.

### Perguntas
1. Com suas palavras: por que o cartão branco com sombra serve melhor que o cartão na `superficie` na grade do Inicio, usando a regra 60-30-10?
2. Aplicação: se o app tivesse um quarto estilo de botão que também usa `.pressao(_:)`, o que você teria de checar sobre "Reduzir movimento"? E se o tamanho de texto de acessibilidade fosse ativado, o que mudaria na grade e por que `minimumScaleFactor` não seria a solução?
3. Raciocínio: o `#0579B8` tem 3,05:1 como ícone sobre `#AED3FC`. Se alguém escurecesse a superfície para `#9CC8F5`, o teste de 3:1 continuaria passando? Raciocine sem calcular tudo: a superfície ficou mais clara ou mais escura, e o que acontece com o contraste do ícone? E por que a distância ao índigo foi o critério que decidiu, se o contraste empatava?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

### Correção das respostas
(sem respostas)

## Tarefa 2.4 — Estilo da tela Estante (2026-10-13)

### O que foi feito
A tela Estante virou uma lista de cartões, um por prateleira, com cabeçalho "Caixa azul · 2" e, em cada livro, uma miniatura 2:3 vinda de uma foto livre (`fotoMiniatura`, antes `fotoCapa`). Surgiu o `CarregadorDeMiniaturas` (ImageIO + `NSCache`), a tela foi estilizada com o mesmo vocabulário do Inicio, e o PLANO e o GLOSSARY registraram as decisões (4 commits, 318 → 323 testes).

### Conceitos envolvidos

**1. Memória de uma imagem decodificada.** Um JPEG de 12 MP ocupa uns 3 MB em disco, mas para desenhar é preciso um bitmap: 4000 × 3000 × 4 bytes (RGBA) = 48 MB. Duzentos livros com foto seriam ~9,6 GB se fossem decodificados inteiros. Por isso `UIImage(data:)` é a ferramenta errada para miniaturas: ele (ao desenhar) abre a foto inteira e só depois você a reduz.

**2. Miniatura com ImageIO.** `CGImageSourceCreateThumbnailAtIndex` decodifica já no tamanho pedido, sem nunca materializar o bitmap grande. As opções usadas:
- `kCGImageSourceThumbnailMaxPixelSize`: o lado maior desejado (300×450 com 132 → 88×132; mantém a proporção).
- `kCGImageSourceCreateThumbnailFromImageAlways`: ignora a miniatura embutida no JPEG, que costuma ser pequena e de qualidade imprevisível.
- `kCGImageSourceCreateThumbnailWithTransform`: aplica a orientação EXIF (foto tirada em pé não sai deitada).
- `kCGImageSourceShouldCacheImmediately`: decodifica agora, na thread de fundo, e não na hora de desenhar na thread principal (evita engasgo na rolagem).

**3. Carregamento preguiçoso por linha.** `LazyVStack` só cria as linhas visíveis; `.task(id:)` dispara o trabalho quando a linha aparece e o cancela quando ela sai. O `id` reinicia a tarefa se algo relevante mudar (aqui, livro e largura). Complexidade: o custo é proporcional ao que está na tela, não ao tamanho da estante.

**4. Cache com `NSCache`.** Dicionário thread-safe que o sistema esvazia sob pressão de memória (um `Dictionary` seu cresceria até o app ser morto). Só aceita objetos, por isso a chave é `NSUUID` (o UUID do livro convertido) e o valor, uma classe (`Guardada`), não uma struct. Essa classe guarda a imagem **e o lado reduzido** com que foi feita. Isso corrigiu o P1: a largura da miniatura cresce com o Dynamic Type (`@ScaledMetric`), então o cache não pode supor "um tamanho só". Regra: se o pedido é maior que o guardado, reduz de novo (teste: 264 > 132 → 176×264 e 2 chamadas à porta); se é menor ou igual, reaproveita.

**5. Cancelamento cooperativo.** Em Swift, cancelar uma `Task` só marca uma flag; o código precisa olhar `Task.isCancelled` (ou chamar algo que lance `CancellationError`). Um `try?` engole o erro, e a redução continuava para linhas que já saíram da tela (P3). A checagem explícita resolve.

**6. ScrollView + LazyVStack × List.** `List` é uma `UITableView`/coleção com reciclagem, swipe e separadores prontos, mas difícil de restilizar (sombra por cartão, mola). Cartões próprios dão coerência com o Inicio, ao custo de perder swipe e reciclagem real (o `LazyVStack` cria views sob demanda, mas não as recicla).

**7. Acessibilidade.** Dynamic Type: com texto grande, a miniatura proporcional ocupava 1/3 da linha e o título truncava; solução com teto (66 pt) e título sem `lineLimit` nos tamanhos de acessibilidade. VoiceOver lia "Caixa azul ponto 2" porque o separador "·" é lido como pontuação; `accessibilityLabel("Caixa azul, 2 livros")` resolve. Contraste: ícone em `.primary` sobre `superficie` (o destaque daria 3,05:1, abaixo do que se quer para o ícone da substituta).

**8. Alvo de toque (HIG).** Mínimo de 44 × 44 pt. Um "+" em todo cartão, dentro de um `NavigationLink`, cria alvos sobrepostos (toque no botão ou na linha?) e engorda cada linha.

### Por que assim
- **Lista com miniatura 2:3**: há autor, ano e títulos longos para mostrar, e livro jurídico é reconhecido pela capa/rosto.
- **Foto livre por livro** (contribuição sua): a capa de livro jurídico é muitas vezes lisa e não identifica; deixar o usuário escolher capa, folha de rosto etc. resolve. O nome `fotoMiniatura` evita colidir com fotos futuras.
- **Sem migração do Core Data**: não há dados reais ainda; migrar agora seria custo sem benefício.
- **Miniatura calculada na hora, não guardada**: dois campos em sincronia (original e reduzida) criam risco de divergência e dúvida no export.
- **Chip fantasma "+ Categoria" só em livro sem categoria**: dá descoberta sem poluir; com categorias, os próprios chips abrem a escolha.
- **Linhas com véu, sem encolher**: encolher uma linha dentro do cartão a descolaria das vizinhas.
- **Cabeçalho em SF semibold**: a serifa fica reservada a títulos de livros/estantes, mantendo hierarquia.

### Alternativas descartadas
- Grade de capas (Apple Books): sem fotos até a Fase 3, some autor/ano.
- Lombadas com texto girado: ruim com títulos longos e Dynamic Type.
- Lista sem capa: perde a "cara de livro".
- Duas fotos (capa + rosto): mais dados no export e uma regra de qual exibir.
- `UIImage(data:)` e carregar a estante inteira: memória (item 1).
- "+" em todo cartão: alvos sobrepostos e altura.
- Seleção em lote: ideia futura, não agora.
- `esquecer(livroId:)`: código sem uso (generalidade especulativa, YAGNI); volta com a troca de foto.

### Padrões e boas práticas
- **Porta + dublê com contador**: o teste "segunda leitura → 1 chamada" só é possível porque a leitura da foto passa por um protocolo; o contador observa o efeito (cache) sem olhar a implementação.
- **Valores esperados literais** (88×132, "Caixa azul · 2"), nunca recalculados como o código calcula.
- **Cache com chave que descreve a qualidade** (aqui, o lado reduzido), não só a identidade.
- **Capturas de tela como instrumento de revisão** (1.0 → 1.1) revelaram o truncamento e a quebra "achá-/los" que nenhum teste pegaria.
- Quando NÃO usar `NSCache`: se o dado precisa persistir ou o custo de recriar é alto e imprevisível; `NSCache` pode descartar a qualquer momento.

### Armadilhas
- Cache que supõe um parâmetro constante (tamanho) que na verdade varia com configuração do usuário.
- `try?` com tarefas canceláveis: o cancelamento some silenciosamente.
- `.task(id:)` sem incluir no `id` tudo de que o resultado depende: a imagem fica velha.
- Separadores tipográficos ("·") em rótulos: o VoiceOver os lê. Teste com VoiceOver ou inspecione o accessibilityLabel.
- Processo: um `mv` sobrescreveu a captura clara ao capturar escuro/texto grande. Dê nomes únicos já na captura.
- Diagnóstico de memória: Instruments (Allocations) ou o gráfico de memória do Xcode ao rolar uma estante com muitas fotos.

### Para ir além
- Apple, *Image and Graphics Best Practices* e a documentação de `CGImageSource` (Image I/O); sessão WWDC18 "Image and Graphics Best Practices".
- Documentação de `NSCache` (Foundation) e de concorrência estruturada em Swift (cancelamento cooperativo).
- Apple, *Human Interface Guidelines*: Layout (alvos de toque) e Accessibility.

### Perguntas
1. Com suas palavras: por que `UIImage(data:)` seguido de redução gasta muito mais memória que `CGImageSourceCreateThumbnailAtIndex`? Faça a conta para uma foto de 12 MP.
2. Aplicação: se o usuário puder trocar a foto de um livro, o que o cache precisaria fazer, e por que `esquecer(livroId:)` voltaria a fazer sentido? E se a miniatura fosse guardada no Core Data, que problema novo apareceria nessa troca?
3. Raciocínio: a miniatura está guardada com lado 132 e o usuário ativa texto de acessibilidade, que pede 198. Descreva o que acontece com e sem a classe `Guardada`. Depois: se o usuário voltar ao tamanho normal (132), o carregador reduz de novo? Justifique.

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->
 (sem respostas)

## Tarefa 2.4 — Estilo da tela Detalhe, número do volume e validação do ISBN (2026-10-13)

### O que foi feito
O Detalhe (`LivroDetalheView.swift`, `LivroDetalheViewModel.swift`) virou um `ScrollView` com cabeçalho centralizado (miniatura, título, autores no formato ABNT, volume) e um cartão por seção. No caminho, duas correções de lógica pedidas por você: o número do volume passou a aparecer (cartão Obra) e o ISBN passou a ser validado de verdade pela nova regra de Domínio `ISBN.normalizar` (`Dominio/Regras/ISBN.swift`), ligada ao `RascunhoLivro` e ao formulário. A revisão em dois eixos gerou o token `Cor.perigo`, o modificador `.cartao()` e testes por regra (347 testes verdes).

### Conceitos envolvidos

**1. Dígito verificador (ISBN).** É redundância deliberada: o último dígito é função dos outros, então um erro de digitação quase sempre torna o conjunto incoerente e é detectado sem consultar nenhum banco.
- ISBN-13: pesos 1,3,1,3… nos 12 primeiros; verificador = (10 − soma % 10) % 10. Exemplo resolvido (Wikipédia, 978-0-306-40615-7): 9+21+8+0+3+0+6+12+0+18+1+15 = 93 → (10 − 3) % 10 = 7. ✓
- ISBN-10: pesos 10…1, soma múltipla de 11; o verificador pode valer 10, escrito "X" (só no fim, porque é um dígito "a mais" que só o último lugar comporta).
- Conversão 10 → 13: prefixo 978 + os 9 dígitos + verificador **recalculado** pela regra do 13. Não se copia o verificador antigo: são fórmulas diferentes.
- Por que pega erros: trocar um dígito muda a soma em `peso × diferença`. Se o peso e o módulo são coprimos, o resultado não é múltiplo do módulo e o erro aparece. Pesos 1 e 3 são coprimos com 10; todos os pesos 1…10 são coprimos com 11 (11 é primo). Logo, **toda troca de um dígito** é detectada nos dois.
- Transposição de vizinhos: no ISBN-10, trocar a e b em pesos w+1 e w muda a soma em (b−a), que nunca é múltiplo de 11 para dígitos 0…10 (se a ≠ b). Pega **todas**. No ISBN-13 os pesos são 1 e 3, a mudança é 2(a−b), múltiplo de 10 quando a−b = ±5: **não pega** trocas entre, por exemplo, 2 e 7. É uma limitação conhecida do mod 10; confirme fazendo à mão.

**2. Prefixo 978/979.** Um EAN-13 qualquer (produto de supermercado, 789… é o prefixo do Brasil) tem a mesma estrutura de 13 dígitos e o mesmo verificador. Só o prefixo diz "isto é livro". Sem exigi-lo, na Fase 3 o leitor de código de barras aceitaria um pacote de arroz como livro. O teste usa 7891234567895 (soma 135 → verificador 5, portanto *válido como EAN*) e a regra o recusa por causa do prefixo, não do verificador. Isso é o que torna o teste significativo.

**3. Unicode e "dígito".** `Character.wholeNumberValue` devolve valor para "٣" (árabe-índico) e "½". Para o Swift são números; para um ISBN, não. Por isso `algarismos` exige `isASCII`. Mesmo cuidado com separadores: U+2010, U+2011 e U+2013 chegam quando se copia de site ou PDF, e o `Tokenizador` já os tratava. A regra de "o que é hífen" fica coerente entre as duas partes.

**4. Forma de retorno `String?`.** `normalizar` devolve `nil` para inválido e o ISBN canônico (13 dígitos, sem hífen) para válido. Uma só função valida e normaliza, então ninguém guarda um valor "validado mas não normalizado". É o princípio "parse, don't validate": converter entrada solta em valor já no formato garantido.

**5. Identidade em listas SwiftUI.** `CampoDoLivro.id` era "rótulo|valor"; dois autores iguais (ou campos com mesmo texto) geravam ids repetidos, e o `ForEach` mistura/ignora linhas com ids duplicados (comportamento indefinido, com aviso no console). Como a lista de campos é estática e montada a cada renderização, usa-se `ForEach(Array(campos.enumerated()), id: \.offset)`. Regra geral: `id` precisa ser único e estável; se o dado não tem identidade natural, a posição serve **quando a lista não é reordenada/editada** pelo usuário.

**6. Contraste (WCAG).** Razão = (L1 + 0,05) / (L2 + 0,05), com L a luminância relativa. systemRed #FF3B30 sobre branco: L ≈ 0,246 → 1,05 / 0,296 ≈ 3,55:1. Texto normal exige 4,5:1; o vermelho do sistema reprova, como já reprovou o `.secondary`. `Cor.perigo`: #D70015 no claro (≈ 5,4:1) e #FF6961 no escuro (≈ 6:1 sobre #1C1C1E). Note que isso só vale para **texto**; ícones e elementos gráficos pedem 3:1.

**7. Autores na ABNT NBR 6023.** 1 autor: nome inteiro; 2 ou 3: só sobrenomes ("Cintra, Grinover e Dinamarco"); 4 ou mais: primeiro + "et al." Sobrenome = o que antecede a vírgula em "Sobrenome, Nome"; sem vírgula, o nome inteiro (fallback seguro: nunca inventa um corte).

**8. Composição.** `ScrollView` + cartões em vez de `List`: mais controle visual, perde swipe e reciclagem. `@ScaledMetric` escala a miniatura com o Dynamic Type; um teto (180 pt nos tamanhos de acessibilidade) impede que a capa tome a tela. `matchedGeometryEffect` só anima entre views da **mesma** hierarquia; entre telas de um `NavigationStack` no iOS 16 não funciona (a zoom transition é iOS 18), por isso o push padrão.

### Por que assim
- **Autores: caminho de três versões.** (1) Todos no cabeçalho, nome inteiro: com texto grande, "Branco, Paulo / Gustavo Gonet" tinha a mesma quebra de linha **dentro** de um nome e **entre** nomes; centralizado e sem divisória, o leitor não distingue. (2) "Cintra, … e mais 2" (e a ideia "+ 2"): o "+" colidiria com o chip "+ Categoria" da 2.5, onde significa *adicionar*. (3) ABNT: convenção que o usuário jurídico já lê todo dia, curta (cabe no cabeçalho), sem inventar notação. Lição de processo: a decisão veio de **olhar capturas com casos extremos** (3 autores, nome longo, texto grande), não de teoria.
- **Volume.** O número era salvo certo, mas `textoDoVolume` mostra o rótulo impresso ("Tomo II") quando existe; o número só ordenava. Com rótulo, uma linha "Número do volume" no cartão Obra; sem rótulo, o cabeçalho já mostra "Vol. N". Bug escondido pela revisão: rótulo só de espaços fazia `volumeRotulo ?? ...` devolver "  " (string vazia visualmente, mas não `nil`) e o cabeçalho ficava sem volume. Solução: normalizar com `preenchido(...)` e a regra "o número aparece fora do cabeçalho?" num lugar só (`numeroDoVolumeForaDoCabecalho`).
- **ISBN no Domínio, não na tela.** É regra de negócio pura, testável sem UI, e será reutilizada pelo leitor de código de barras (Fase 3).
- **ISBN inválido bloqueia o salvamento também na edição.** Validar só quando o campo muda deixaria passar um ISBN ruim que entrou por outra porta (importação, dado antigo). É coerente com o "pede para completar" de 10/10.
- **Teclado `.numbersAndPunctuation`.** O `numberPad` não tem "X" nem hífen: o usuário não conseguiria digitar um ISBN-10 terminado em X. Achado da segunda revisão.
- **`Cor.perigo` e `.cartao()`.** Um token em vez de `.red` espalhado (contraste, tema escuro, mudança num lugar); um modificador no lugar do trio `.background.cantos.sombraSuave` copiado em 4 arquivos.
- **Sem título na barra.** Mostrá-lo ao rolar exige medir o deslocamento à mão (`GeometryReader` + `PreferenceKey`) no iOS 16.

### Alternativas descartadas
- `List` restilizada: difícil de aplicar sombra/cantos por cartão.
- Valor ao lado do rótulo: valores longos e texto grande espremem a linha; rótulo `.caption` em cima resolve.
- Validar o ISBN só no verificador, sem prefixo: aceitaria EAN de produto.
- Validar só quando o campo muda: deixa passar ISBN inválido de outra origem.
- `matchedGeometryEffect` entre telas / zoom transition: indisponíveis no iOS 16.
- Lista de autores completa no cabeçalho, ou cartão "Autores" com "e mais N": ver a história acima.

### Padrões e boas práticas
- **Regra pura no Domínio, tela burra.** A ViewModel só pergunta; a regra tem testes próprios.
- **Teste com valor de fonte independente.** Os exemplos vêm da Wikipédia e de conta à mão (978080442957 → soma 117 → 3; 9791000000008 → soma 42 → 8), nunca do próprio `verificador13`. E o benefício apareceu: o fixture antigo 9788520300000 tinha verificador errado (soma 82 → 8), um dado inválido escondido nos testes.
- **Um teste por regra** (ABNT: 1, 2, 3, 4+ autores, sem vírgula) para que a falha aponte a regra quebrada.
- **Vermelho → verde para tokens** (teste de contraste antes de `Cor.perigo`).
- **Extrair modificador** quando o mesmo encadeamento aparece 3+ vezes. Quando NÃO: se só 1 ou 2 usos, ou se os usos divergem em detalhes, a abstração custa mais que a repetição.
- **Revisão em dois eixos**: padrões (P) e plano (E) pegam coisas diferentes (o P pegou o teclado; o E, a colisão de id).

### Armadilhas
- `??` em string: `nil` e `"  "` são coisas diferentes; texto digitado precisa ser aparado antes de decidir "vazio".
- `wholeNumberValue` e `isNumber` aceitam dígitos não ASCII e frações.
- ISBN-10: o "X" só vale no último lugar; e minúsculo "x" também aparece digitado.
- Verificador mod 10 não detecta toda transposição (diferença de 5).
- `ForEach` com ids repetidos: sintoma é linha duplicada/sumida e aviso no console.
- Testes que só passam com dado inválido: ao endurecer uma regra, rode tudo e desconfie dos fixtures.
- Processo: houve queda de energia com a edição já gravada. Antes de repetir um comando interrompido, confira `git status` e `grep` para ver o que já foi aplicado; e **commite cedo**, em passos pequenos: o commit é o ponto de restauração mais barato que existe.

### Para ir além
- ISO 2108 (ISBN) e o manual do usuário da Agência Internacional do ISBN (isbn-international.org); a página "International Standard Book Number" da Wikipédia traz os exemplos usados aqui.
- ABNT NBR 6023 (referências), seção de autoria.
- WCAG 2.2, critério 1.4.3 (Contrast Minimum), com a fórmula de luminância relativa.

### Perguntas
1. Com suas palavras: por que um dígito verificador detecta qualquer erro de um só dígito? Mostre, com pesos e módulo, por que o peso 3 do ISBN-13 não atrapalha (e o que atrapalharia, por exemplo um peso 5 em módulo 10).
2. Aplicação: calcule o verificador do ISBN-13 de 978-85-359-0277-? (os 12 primeiros dígitos são 978853590277). Depois diga o que mudaria na regra se quiséssemos aceitar também ISSN (8 dígitos, mod 11, pesos 8…2), e onde isso entraria no código.
3. Raciocínio: troque dois dígitos vizinhos 2 e 7 num ISBN-13 válido (um com pesos 1 e 3). A validação percebe? E no ISBN-10 com os mesmos dígitos? Explique a diferença pela aritmética. Bônus: por que `id = "rótulo|valor"` falhava no Detalhe e qual condição faz a posição (`\.offset`) ser um id aceitável?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

### Correção das respostas
(sem respostas)

---

## Tarefa 2.4 — Estilo do Formulário, foto da miniatura (decisão) e limpeza de texto no Domínio (2026-10-13)

### O que foi feito
O `LivroFormularioView.swift` foi estilizado sobre o `Form` nativo, com o nome do campo aparecendo pequeno em cima só quando ele está preenchido, título e subtítulo em serifa e crescendo para baixo, e sugestões de prateleira reaproveitando o mesmo `campo(...)`. Em `RascunhoLivro.swift`, a limpeza de texto (apara pontas e junta espaços/quebras de linha em um espaço) passou a viver no Domínio, com o teste `testQuebraDeLinhaEEspacosRepetidosViramUmEspaco`. A foto da miniatura foi decidida (parâmetros e regras), mas **ainda não implementada** (passo 2, commit separado). Commits c40947b e 7912d8f; 348 testes. O resultado é **provisório**: o Ricardo pode pedir para desfazer.

### Conceitos envolvidos

**1. `Form` nativo vs. `ScrollView` + cartões.** O `Form` é uma `List` com estilo agrupado (`insetGrouped`). Em UIKit, por baixo, é uma `UICollectionView`/`UITableView`: células recicladas, cabeçalhos/rodapés de seção, `onDelete`/`onMove` (apagar e arrastar autores), integração com foco e com a fuga do teclado (a lista rola para o campo em foco). Tudo isso o `ScrollView` + `VStack` não dá de graça: você reimplementaria. No Detalhe o oposto valia: era tela de **leitura**, onde o controle visual dos cartões importava mais que o comportamento de edição. Regra: a ferramenta segue o tipo de interação (ler vs. editar).

**2. Cores semânticas e o fundo "agrupado" que muda com o contexto.** `systemGroupedBackground` não é uma cor fixa: o sistema resolve por *trait collection*, incluindo o nível de elevação. Numa folha (sheet) em modo escuro, o nível "elevado" faz o fundo agrupado virar #1C1C1E e as linhas #2C2C2E. Nosso `cartao` escuro também é #1C1C1E, então ao pintar o fundo explicitamente os cartões **sumiram** (mesma cor). Lição: ao sobrescrever um fundo semântico, você assume a responsabilidade pelo par fundo/linha em todos os modos; deixar o `Form` fazer o par certo é mais robusto.

**3. `TextField` com `prompt` e `axis: .vertical`.** `TextField(_ titleKey, text:, prompt:, axis:)` separa o *rótulo* (usado por acessibilidade e em alguns estilos) do *prompt* (o placeholder visual). Sem `prompt`, o SwiftUI usa o título como placeholder, e foi isso que repetia o nome (captura 1.0). Com `axis: .vertical` o campo cresce em várias linhas (iOS 16+, compatível com o Xcode 14.2), mas **o Return passa a inserir "\n"** em vez de encerrar a edição (achado F1).

**4. `@FocusState` com valor `Hashable` e `WritableKeyPath`.** `@FocusState` aceita `Bool` ou qualquer `Hashable?`. `WritableKeyPath<RascunhoLivro, String>` é `Hashable`, então o próprio caminho do campo serve de identificador de foco: `.focused($campoEmFoco, equals: caminho)`. Um só `@FocusState` substitui um por campo, e `campoEmFoco == \.prateleira` responde "a prateleira está em foco?". Atribuir `nil` tira o foco (fecha o teclado). Observação de custo: comparar key paths é igualdade de identidade do caminho, barata.

**5. Limpeza de texto: `trimmingCharacters` vs. `split` + `joined`.** `trimmingCharacters(in: .whitespacesAndNewlines)` só mexe nas **pontas**. A nova versão, `texto.split(whereSeparator: \.isWhitespace).joined(separator: " ")`, quebra a string em "palavras" (`split` omite pedaços vazios por padrão, `omittingEmptySubsequences: true`) e as une com um espaço. Efeito: apara as pontas **e** colapsa qualquer sequência de espaços/tabs/quebras no meio. Complexidade O(n) em tempo e espaço. Exemplo: `"Direito \n civil"` → `["Direito","civil"]` → `"Direito civil"`. Detalhe: `Character.isWhitespace` inclui "\n"; `isNewline` é mais estreito, e por isso o `onChange` da View (que só olha `isNewline`) deixa sobrar `"a   b"` de `"a \n b"`, e o Domínio completa a limpeza.

**6. Onde mora uma regra: View vs. Domínio.** "Texto salvo não tem espaços duplos nem quebras" é regra sobre **dados**, não sobre apresentação. Na View ela não era testável sem simulador e valeria só por aquela porta de entrada; no `RascunhoLivro` vale para qualquer origem (importação, Fase 3) e tem teste puro. A View ficou apenas com a parte de interface: trocar a quebra por espaço e fechar o teclado.

**7. Animação ligada a um valor.** `.animacaoSuave(valor: texto.isEmpty)` (modificador do projeto) anima as mudanças de layout quando aquele valor muda: o nome pequeno entra com `transition(.opacity)` e o campo se acomoda. Atrelar a animação a um valor (e não a `withAnimation` global) limita o efeito ao que interessa.

**8. Imagem para guardar: resolução e custo (decisão da foto, ainda não implementada).** O princípio esclarecido pelo Ricardo: foto de alta qualidade é para **usar** (OCR na Fase 3 roda na resolução máxima da câmera in-app); depois se **reduz** para guardar e exibir. Conta: lado maior 1200 px, JPEG qualidade 0,8 ≈ 150 KB. 200 livros ≈ 30 MB no export. A original (3 a 10 MB) daria ~1 GB. Miniatura de 180 pt a @3x = 540 px, então 600 px bastaria, mas borraria uma vista ampliada; 1200 px dá folga de ~2x. JPEG é com perda e seu tamanho depende do conteúdo; a qualidade 0,8 é o ponto comum de "sem perda visível óbvia".

### Por que assim
- **Q1, `Form` nativo.** Apagar/arrastar autores, foco e fuga do teclado vêm prontos. A "List restilizada" foi descartada no Detalhe, mas lá era tela de leitura.
- **Q2, nome em cima.** Resolve o problema de "1965" sem dizer que é o ano (um campo preenchido perde o placeholder). Na versão final, o nome pequeno só aparece com o campo preenchido: vazio, o placeholder já diz o que é.
- **Q3, título em serifa.** Segue a regra de 12/10: New York só em títulos de livros. O que o usuário digita *é* um título de livro.
- **Q4, foto agora, em commit separado.** Um assunto por commit: estilo e foto têm riscos e reversões diferentes.
- **Q5′, 1200 px JPEG 0,8.** Ver conceito 8.
- **Q6, gravar só no Salvar.** Cancelar descarta; o livro novo ainda não tem `id`, então não há nome de arquivo definitivo antes de salvar. Gravar antes deixaria arquivos órfãos.
- **Q7, menu com "Remover foto".** Quem põe a foto precisa poder tirá-la.
- **Q8, sugestões de prateleira e erros.** Decididos na captura, olhando a tela real, não em teoria.
- **Reuso do `campo(...)` na prateleira (P1).** Antes a prateleira repetia o campo e tinha um segundo `FocusState`; duplicar estilo é onde as telas divergem com o tempo.
- **Variável renomeada (P6).** O parâmetro `problema: campo` sombreava o nome `campo`; nome distinto evita ler errado.

### Alternativas descartadas e história das capturas
O caminho foi de tentativa e erro **olhando o simulador**:
- **1.0, tokens (fundo branco + linhas `cartao` branco).** Os cartões sumiram: no Detalhe quem separa os cartões é a **sombra**, e o `Form` não tem sombra por seção. Além disso o `TextField` sem `prompt` repetia o nome como placeholder.
- **1.1, `systemGroupedBackground`.** No escuro sumiu de novo (conceito 2). No texto grande, o título era cortado com "…". O Ricardo preferiu o visual antigo (cinza com cartões brancos) e achou que o nome sempre em cima poluía.
- **1.2, nenhum fundo customizado.** O `Form` já faz o par certo (inclusive #1C1C1E/#2C2C2E na folha escura); nome pequeno só com o campo preenchido; título e subtítulo com `axis: .vertical`. Esta ficou. **Exceção ao Estilo 0** (tokens por toda parte) registrada no PLANO: aqui o fundo e as linhas são do sistema.
- **F1 (Return com `axis: .vertical`).** Insere "\n". Alternativas: aceitar a quebra no título (suja o dado e a lista), ou `.submitLabel(.done)` + tratamento (não funciona de forma confiável com eixo vertical no iOS 16, não verifiquei em todas as versões; confira na documentação). A escolha: reagir no `onChange`, trocar por espaço e tirar o foco.
- **Foto original guardada**: ~1 GB para 200 livros. **600 px**: bastaria para a miniatura, mas borra ao ampliar.
- **Gravar a foto ao escolher**: deixaria órfãos ao cancelar.

### Padrões e boas práticas
- **Parse, don't validate (de novo).** `RascunhoLivro.montar` devolve um `Livro` já limpo; ninguém precisa lembrar de limpar depois.
- **Revisão em dois eixos.** O revisor de padrões (P1 a P7) pegou duplicação, espaços duplos e sombreamento; o revisor-spec (E5) pegou a regra de dados na View sem teste, que foi para o Domínio com vermelho → verde. P3/P4/P5/P7 foram mantidos. P4: `onChange(of:)` de um parâmetro está deprecated no iOS 17, mas é o único que o Xcode 14.2 aceita; deve migrar quando o projeto subir de versão mínima/ferramenta.
- **Teste que falha pelo motivo certo.** A segunda fronteira proposta ("texto sem quebra não muda") já era coberta por `testAparaEspacosNasPontas`; repetir seria teste redundante.
- **E8.** A linha do Histórico dizia "vestido com os tokens", o que era falso depois da exceção; documentação que mente é pior que nenhuma.
- Quando NÃO usar `Form`: telas de leitura/apresentação em que a identidade visual do app pede controle por cartão.

### Armadilhas
- Sobrescrever fundo semântico: some em um dos modos (claro/escuro, tela cheia/folha). Sempre capture nos dois modos e em folha.
- `axis: .vertical` muda o Return. Texto colado também traz "\n".
- `isNewline` ≠ `isWhitespace`: limpar só um deles deixa espaços duplos.
- `onChange` que reatribui o próprio valor dispara de novo; a guarda `guard ... contains(where: \.isNewline)` impede o laço (depois da troca, não há mais quebras, e a segunda chamada sai).
- `ForEach(indices, id: \.self)` para autores é aceitável aqui só porque `onDelete` atualiza a lista inteira; se houvesse estado por linha, a identidade por posição causaria saltos.
- Foto: não deixe arquivos órfãos; chame a gravação só no Salvar e apague a antiga ao substituir/remover.

### Para ir além
- Documentação da Apple: `TextField`, `FocusState` e `Form` (developer.apple.com/documentation/swiftui).
- Apple, "Human Interface Guidelines: Color" (seção sobre cores de fundo semânticas e elevação em modo escuro).
- "Parse, don't validate", Alexis King (2019).

### Perguntas
1. Com suas palavras: por que o `Form` "ganha" do `ScrollView` + cartões no Formulário, mas perdeu no Detalhe? Cite pelo menos duas coisas concretas que o `Form` dá de graça.
2. Aplicação: o Ricardo quer que "Páginas" também aceite colar "320 p." sem quebrar a validação. Em que camada isso entra (View, ViewModel ou `RascunhoLivro`) e que teste você escreveria primeiro? Dê o valor esperado de fonte independente.
3. Raciocínio: `"  A\t\tB \n C  "` passa por `texto(_:)`. O que sai? E o que sai se o `split` usasse `omittingEmptySubsequences: false`? Bônus: por que, na foto, 200 livros com 1200 px/JPEG 0,8 custam cerca de 30 MB, e o que muda se você mantiver a original de 5 MB?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

(sem respostas)

---

## Tarefa 2.4 — Foto da miniatura no Formulário (2026-10-13)

### O que foi feito
O Formulário ganhou um cabeçalho com a foto (72 pt) e o menu "Adicionar foto" / "Escolher outra foto" / "Remover foto", via `PhotosPicker`. A foto é reduzida pelo novo `RedutorDeFoto` (ImageIO: lado maior 1200 px, JPEG 0,8), fica no `LivroFormularioViewModel` e só é gravada no Salvar, e só se mudou. O `CarregadorDeMiniaturas` virou `ObservableObject` com `esquecer(livroId)`, para a lista refletir a troca. Arquivos: `RedutorDeFoto.swift`, `LivroFormularioView.swift`, `LivroFormularioViewModel.swift`, `CarregadorDeMiniaturas.swift`, `MiniaturaDoLivro.swift`, `Dependencias.swift`. Testes: 348 para 356.

### Conceitos envolvidos

**1. Redução de imagem com ImageIO.** Uma foto de 12 MP (4000x3000) decodificada inteira ocupa cerca de 4000x3000x4 bytes = 48 MB de bitmap, só para depois encolher. `CGImageSourceCreateThumbnailAtIndex` pede ao decodificador já o tamanho final (para JPEG, ele consegue decodificar em escala reduzida, então o pico de memória é bem menor). Opções usadas:
- `kCGImageSourceCreateThumbnailFromImageAlways`: ignora a miniatura minúscula embutida no arquivo e gera a partir da imagem real;
- `kCGImageSourceCreateThumbnailWithTransform`: aplica a orientação EXIF (sem isso, foto tirada em pé sairia deitada);
- `kCGImageSourceShouldCacheImmediately`: força a decodificação na hora da chamada (fora da fila principal), e não de forma preguiçosa na primeira vez que a imagem for desenhada;
- `kCGImageSourceShouldCache: false` na fonte: não manter o bitmap grande em cache interno.
`kCGImageSourceThumbnailMaxPixelSize` é o lado maior; a proporção é preservada. Depois, `CGImageDestination` com `kCGImageDestinationLossyCompressionQuality = 0.8` gera o JPEG. Custo: O(pixels da saída) na redução, memória proporcional ao tamanho reduzido.

**2. Os testes que "já nasceram verdes".** Os testes "600x400 não é ampliada" e "dados que não são imagem devolvem nil" passaram sem ficar vermelhos, porque o ImageIO já se comporta assim (ele só reduz, não amplia). Não é tautologia: eles travam um **contrato de que a tela depende** (não inflar arquivo, não crashar com lixo). Se um dia trocarem a implementação (por `UIGraphicsImageRenderer`, que amplia se você mandar), o teste pega. Regra: um teste verde de primeira é aceitável se você sabe dizer qual mudança futura o deixaria vermelho.

**3. Cache invalidado com contador-gatilho.** `NSCache` guarda a miniatura por `livroId`. Ao trocar a foto, a entrada fica velha. `esquecer(livroId)` remove a entrada e incrementa `@Published trocas`. A `MiniaturaDoLivro` observa o carregador e usa `trocas` dentro do `id` do `.task(id:)`: `.task(id:)` cancela e reexecuta o corpo sempre que o `id` muda. Resultado: todas as miniaturas visíveis pedem de novo, mas as que não mudaram voltam do cache sem tocar na porta. O `trocas` não tem significado próprio, é só um **gatilho de invalidação** (daí o nome, depois do P5; `versao` sugeria algo que não existe).

```mermaid
sequenceDiagram
  participant F as Formulário
  participant VM as ViewModel
  participant D as Dependencias
  participant C as CarregadorDeMiniaturas
  participant M as MiniaturaDoLivro
  F->>VM: salvar()
  VM->>VM: grava foto (porta)
  VM->>D: fotoTrocada(livroId)
  D->>C: esquecer(livroId)
  C->>C: remove do NSCache, trocas += 1
  C-->>M: @Published trocas mudou
  M->>M: .task(id) reinicia e pede de novo
```

**4. O ViewModel fala com a UI sem importá-la: closure injetada.** A regra é "ViewModel só Foundation" (na prática, sem conhecer o carregador, que é de Apresentação/UIKit). Então ele expõe `fotoTrocada: (UUID) -> Void` e a montagem liga ao `esquecer`. É inversão de dependência na forma mais simples: em vez de um protocolo com um método, uma closure. Depois do P4 o valor padrão `{ _ in }` saiu: com padrão, esquecer de ligar compila e falha **em silêncio** (miniatura velha na tela). Sem padrão, o compilador obriga. Princípio: torne o estado errado impossível de compilar.

**5. Concorrência: corrida entre tarefas e cancelamento cooperativo (P3).** O desenho antigo era `onChange` + `Task { }` solta. Escolher A e logo B: duas tarefas rodam; se A demora mais, termina por último e sobrescreve B (resultado depende de quem acaba primeiro: *race condition*). Agora `.task(id: itemDaFoto)`: ao mudar o `id`, o SwiftUI **cancela** a tarefa anterior. Mas cancelamento em Swift é **cooperativo**: só liga uma sinalização (`Task.isCancelled`); nada para sozinho. E o `Task.detached` **não herda** o cancelamento da tarefa pai (detached = sem contexto herdado). Por isso a conferência `Task.isCancelled` vem **depois** do `.value`, na tarefa que está sendo cancelada, antes de usar o resultado. Detalhe sutil: `itemDaFoto` só volta a `nil` no fim; se voltasse no começo, mudaria o `id` e a tarefa cancelaria a si mesma. E voltar a `nil` permite escolher de novo a mesma foto depois de removê-la (o `PhotosPicker` só dispara quando o binding muda).

**6. `PhotosPicker` e `preferredItemEncoding`.** Ao escolher uma foto no simulador, apareceu "Não foi possível abrir a foto.". O log dizia `PHAssetExportRequestErrorDomain` e `PAMediaConversionServiceErrorDomain` erro 2 (mode=compatible). Causa: sem dizer o formato, o picker usa `.automatic`/compatível e **converte a foto cheia** (HEIC para JPEG) antes de entregar; no simulador essa conversão falha. A suspeita inicial (tamanho da foto) estava errada. Correção: `preferredItemEncoding: .current`, que entrega no formato original; o ImageIO lê HEIC e o nosso redutor já gera o JPEG pequeno, então a conversão do sistema era trabalho duplicado. Lição de método: **ler domínio e código do erro antes de supor a causa**.

**7. Falha parcial e idempotência do Salvar (P1/E4).** Salvar faz duas gravações (livro, depois foto). A segunda pode falhar com a primeira já confirmada. Com um só `do/catch`, a mensagem mentia ("Não foi possível salvar o livro"). Agora são dois `do` separados: "O livro foi salvo, mas a foto não." e a folha continua aberta. O detalhe essencial é `original = livro` logo após gravar o livro: o próximo Salvar passa a **atualizar** o mesmo livro em vez de criar um segundo (duplicata). É a ideia de **retentativa segura**: repetir a operação depois de falha parcial não pode multiplicar efeitos. Sem transação que cubra livro e arquivo (Core Data e sistema de arquivos são mundos separados), a ordem e o estado explícito fazem esse papel.

**8. `try?` que mente (P2/E5).** Ler a foto atual com `try?` transformava erro em "não tem foto", e o formulário mostrava "Adicionar foto" para um livro que tem. Agora o erro vira aviso. Salvar sem mexer na foto não a apaga porque a regra é `foto != fotoInicial` para gravar: a ausência de mudança nunca gera escrita. Duas coisas diferentes (nil por "não tem" e nil por "falhou ao ler") precisam de representações diferentes.

**9. `@ScaledMetric`.** Tamanho que escala com o Dynamic Type (72 pt base, teto de 120 para não estourar o layout em textos muito grandes).

### Por que assim
- **1200 px, JPEG 0,8 (~150 KB).** Original de 3 a 10 MB: 200 livros ~ 1 GB no banco e no export. Com 600 px, uma vista ampliada borra. Princípio do Ricardo: foto de alta qualidade só é *usada* (OCR na Fase 3, na resolução máxima da câmera) e depois descartada.
- **Gravar só no Salvar.** Cancelar descarta, funciona com livro novo (sem `id` ainda) e não deixa arquivo órfão.
- **G1, 72 pt.** Menor que o Detalhe (140): aqui a foto serve só para conferir.
- **G2, botão x menu.** Sem foto, um toque abre a fototeca (um passo a menos); com foto, o menu oferece as duas ações.
- **Closure `fotoTrocada` sem padrão.** Ver conceito 4.
- **Redução fora da fila principal.** Decodificar é custoso; na main travaria a rolagem (P6 estendeu isso à imagem do cabeçalho).

### Alternativas descartadas
- **`UIGraphicsImageRenderer` para reduzir:** exige decodificar a imagem inteira antes (pico de ~48 MB) e pode ampliar.
- **Deixar o picker converter (`.automatic`):** falha no simulador e faz trabalho que jogamos fora.
- **`onChange` + `Task` solta:** corrida (conceito 5).
- **Invalidar o cache inteiro (`removeAllObjects`):** funcionaria, mas as miniaturas não afetadas recarregariam da porta sem necessidade; `esquecer` por id é cirúrgico.
- **Notificação (`NotificationCenter`) para avisar a troca:** acoplamento implícito e global, difícil de testar; a closure é explícita e testável.
- **Extrair `CabecalhoDaFoto` agora (P8):** adiado até o estilo provisório ser confirmado, para não abstrair algo que ainda vai mudar.

### Padrões e boas práticas
- **Inversão de dependência por closure** e "faça o erro não compilar".
- **Falha parcial explícita:** mensagem precisa diz o que deu certo e o que não.
- **Teste vermelho pelo motivo certo:** o teste de falha só na foto ficou vermelho pela mensagem antiga; a parte "não duplica" já funcionava e ganhou cobertura. Um interruptor (`falharAoGravarFoto`) no repositório falso injeta a falha sem mocks complexos.
- **Revisão em dois eixos:** o revisor pegou a corrida, o `try?` e o padrão da closure; o revisor-spec pegou o PLANO desatualizado (E1). Documentação que descreve o desenho antigo engana o próximo leitor.
- Quando NÃO usar `.task(id:)` para isso: se o trabalho **não** puder ser cancelado sem efeitos colaterais (gravar em disco, por exemplo), ele não deve rodar dentro de uma tarefa cancelável por mudança de id.

### Armadilhas
- Cancelar não interrompe: sem checar `Task.isCancelled` (ou usar um ponto de suspensão que lança), a tarefa velha continua e pode sobrescrever.
- `Task.detached` não herda cancelamento, prioridade nem ator.
- Voltar o `id` do `.task` a `nil` no começo cancela a própria tarefa.
- Esquecer `WithTransform`: fotos em pé aparecem deitadas.
- `try?` que vira "vazio": diagnostique perguntando "esse nil pode significar falha?".
- Conferir o log do sistema (domínio + código) antes de teorizar; o simulador também difere do aparelho (conversão de mídia).
- Closure com valor padrão no `init` esconde ligação esquecida.

### Para ir além
- Apple, "Image and Graphics Best Practices" e a documentação de `CGImageSource` (Image I/O): developer.apple.com/documentation/imageio.
- WWDC18, "Image and Graphics Best Practices" (memória x tamanho do bitmap).
- Apple, "Concurrency" no The Swift Programming Language, seção sobre cancelamento de tarefas.

### Perguntas
1. Com suas palavras: por que `CGImageSourceCreateThumbnailAtIndex` é melhor que carregar a imagem inteira e redimensionar? Quanto de memória custaria o bitmap de uma foto 4000x3000?
2. Aplicação: o Ricardo decide guardar a foto em 2400 px. O que muda no tamanho aproximado para 200 livros (pense na área, não só no lado) e que teste do `RedutorDeFoto` você alteraria primeiro?
3. Raciocínio: no Salvar, a gravação do livro funciona e a da foto falha. Se `original = livro` não existisse, o que aconteceria ao tocar em Salvar de novo num livro novo? E por que a conferência de `Task.isCancelled` precisa vir depois do `.value` do `Task.detached`?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

(sem respostas)

---

## Tarefa 2.4 — Foto ampliada no Detalhe (2026-10-13)

### O que foi feito
Tocar na foto do Detalhe abre a imagem maior, sobre um fundo escuro esmaecido, com zoom por pinça e duplo toque e fechamento ao puxar. A tela de zoom é um `FotoAmpliadaController` (UIKit, com `UIScrollView`), apresentado por um anfitrião invisível (`UIViewControllerRepresentable`) no `.background` do Detalhe. O carregador de miniaturas ganhou `fotoInteira` (lê fora do cache) e `temFoto(doLivro:)`. Commit a90f724; plano em 1e12fe3.

### Conceitos envolvidos

**1. Zoom com `UIScrollView`.** A `UIScrollView` é, no fundo, uma janela (`bounds`) deslizando sobre um conteúdo maior (`contentSize`). Para zoom, você devolve em `viewForZooming` a subview a escalar e define `minimumZoomScale`/`maximumZoomScale` (aqui 1 a 4). O sistema aplica um `transform` nessa view e ajusta `contentSize`, e dá de graça a pinça, a mola nos limites e a inércia. Detalhe clássico: se o conteúdo é menor que a janela, a rolagem o gruda no canto superior esquerdo. Por isso `scrollViewDidZoom` recalcula um `contentInset` que centraliza a imagem. O duplo toque usa `zoom(to: rect, animated:)`: você passa o retângulo do conteúdo que quer ver e a scroll view calcula a escala.

**2. Conflito de gestos.** Duas coisas querem o arrasto: a rolagem da foto com zoom e o "puxar para fechar". A regra está em `gestureRecognizerShouldBegin`: o pan de fechar só começa se `zoomScale == minimumZoomScale` e se o movimento for mais vertical que horizontal. É o mecanismo normal do UIKit: reconhecedores competem, e o delegate arbitra.

**3. Gesto interativo com decisão na soltura.** Durante o pan, a foto segue o dedo (`transform`) e a opacidade do fundo cai proporcionalmente. Ao soltar, decide-se por distância (> 120 pt) ou velocidade (> 800 pt/s). Esse "ou" existe porque um flick curto e rápido expressa intenção de fechar mesmo sem percorrer distância. Se fecha, a foto termina de sair e só então `dismiss(animated: false)`, para a animação do sistema não duplicar a nossa.

**4. Apresentação modal: `fullScreenCover` x `.overFullScreen`.** Ao apresentar um modal de tela cheia (`.fullScreen`), o UIKit remove a view de baixo da hierarquia para economizar, e o fundo fica preto. Com `.overFullScreen` a tela de baixo permanece na hierarquia, então um fundo semitransparente deixa ver o Detalhe. O `fullScreenCover` do SwiftUI no iOS 16 usa o primeiro comportamento. O `presentationBackground` resolveria, mas é iOS 16.4 e o projeto tem mínimo 16.0 e regra de compilar em dois Xcodes.

**5. Ponte SwiftUI para UIKit.** `UIViewControllerRepresentable` tem `makeUIViewController` e `updateUIViewController`; o SwiftUI chama o segundo sempre que o estado muda. O anfitrião observa um `Binding<UIImage?>`: valor presente e nada apresentado, chama `present`. Ao fechar, zera o binding no `completion` do `dismiss`. É o padrão "estado como fonte da verdade": a UI apresentada é consequência do binding, e o fechamento devolve o estado ao SwiftUI.

**6. Cache: o que NÃO guardar.** Um bitmap decodificado ocupa largura x altura x 4 bytes (RGBA). A foto guardada tem o lado maior de 1200 px, então o pior caso é a quadrada: 1200 x 1200 x 4 ≈ 5,8 MB; uma capa em 2:3 (800 x 1200) dá ≈ 3,8 MB, e a miniatura da lista (88 x 132 a 1x, ou 264 x 396 a 3x) fica entre ~46 KB e ~420 KB. O ponto é que um bitmap custa largura x altura x 4, não o tamanho do JPEG. Se a foto grande entrasse no `NSCache` (uma entrada por livro), ocuparia o lugar da miniatura e a lista passaria a desenhar uma imagem enorme em cada linha.

**7. Corrida entre duas tarefas sobre o mesmo cache (P5).** O Detalhe perguntava "tem foto?" pedindo `miniatura(ladoMaior: 1)`. As duas tarefas (a da miniatura e a dessa pergunta) começam juntas; se a pergunta chegasse primeiro, lia o banco, guardava um bitmap de 1 px e a miniatura de verdade lia outra vez para substituí-lo. Resultado: leitura dobrada e lixo no cache. A correção é dar nome à intenção: `temFoto(doLivro:)` responde pelo cache se o livro está lá e, senão, lê sem guardar (não sabe o tamanho que a lista pedirá). Princípio: uma função genérica usada com um argumento "mágico" para outro fim cria efeitos colaterais escondidos.

**8. Teste que não distingue "fez" de "não fez" (P4/E1).** O teste original usava entrada 800x1200 e esperava saída 800x1200: passaria mesmo que nada fosse reduzido. Com entrada 1600x2400 e saída esperada 800x1200 (valor literal, independente do código), só passa se houve redução. Regra prática: o dado de entrada deve diferir da saída esperada na dimensão que o teste pretende provar.

### Por que assim
- **UIScrollView e não gestos do SwiftUI:** limites, mola, inércia e duplo toque já existem e são os que o usuário conhece. À mão seriam centenas de linhas e comportamento "quase igual".
- **Apresentação pelo UIKit (opção a):** única que dá fundo esmaecido real sem API nova, e ainda traz `accessibilityViewIsModal` (VoiceOver preso ao modal).
- **`fotoInteira` fora do cache:** ver conceito 6.
- **Sem foto, toque ignorado** (`allowsHitTesting(false)`, escondida do VoiceOver): evita um botão que não faz nada.
- **Durações e amortecimento com nomes:** números mágicos de animação são difíceis de ajustar e de revisar.
- **`accessibilityPerformEscape`:** o gesto de "voltar" do VoiceOver (Z com dois dedos) fecha a tela.

### Alternativas descartadas
- **`.overlay` no Detalhe (b):** a barra de navegação ficaria por cima do escuro; escondê-la reorganiza o conteúdo.
- **Overlay na raiz do app (c):** estado global e uma ação passada pelo ambiente até uma tela funda; acoplamento ruim.
- **`MagnificationGesture` + `DragGesture`:** limites, mola e duplo toque à mão.
- **Reaproveitar `miniatura(ladoMaior: 1200)`:** cacheava a foto grande (o teste `testMiniaturaContinuaPequenaDepoisDeAmpliar` ficou vermelho com ela).
- **Recusadas na revisão:** dono do controlador (a foto cobre tudo, só ela mesma se fecha) e decodificação na fila principal (conferido: as funções `async` do carregador correm fora dela).

### Padrões e boas práticas
- **Delegate como árbitro** (`gestureRecognizerShouldBegin`).
- **Anfitrião invisível:** padrão comum para usar UIKit onde o SwiftUI da versão mínima não alcança. Quando NÃO usar: se o mínimo suportasse a API SwiftUI equivalente, ela seria mais simples e portável.
- **Isolar efeito colateral na API:** `temFoto` x `miniatura`.
- **Vermelho pelo motivo certo:** `testTemFotoDepoisDaMiniaturaNaoLeAPorta` falhou com 2 leituras em vez de 1 na versão ingênua.
- **Comparar com `minimumZoomScale`** em vez de o literal 1: o código continua certo se o mínimo mudar.

### Armadilhas
- Imagem menor que a tela sem `contentInset` fica no canto.
- `dismiss(animated: true)` depois da nossa animação produz piscada duplicada.
- Esquecer de zerar o binding no `completion` deixa o estado dizendo "aberto" com nada na tela, e o próximo toque não reapresenta.
- Chamar `present` dentro de `updateUIViewController` sem checar `presentedViewController` apresenta várias vezes (o `updateUIViewController` roda a cada mudança de estado).
- Segundo toque durante a leitura: sem o indicador `abrindoFoto`, lê duas vezes.
- Bitmap decodificado custa largura x altura x 4 bytes, muito mais que o arquivo.

### Para ir além
- Apple, "Scroll View Programming Guide for iOS" (seção Zooming) e documentação de `UIScrollViewDelegate`.
- Apple, documentação de `UIViewControllerRepresentable` e de `UIModalPresentationStyle.overFullScreen`.
- WWDC18, "iOS Memory Deep Dive" (custo de bitmaps decodificados).

### Perguntas
1. Com suas palavras: por que `fullScreenCover` deixa o fundo preto e `.overFullScreen` não? O que o UIKit faz com a view de baixo em cada caso?
2. Aplicação: se o mínimo do projeto subisse para iOS 16.4, o que você poderia simplificar nesta tela e o que ainda precisaria do UIKit (pense no zoom)?
3. Raciocínio: explique a corrida que o `temFoto` resolveu. Em que ordem as duas tarefas teriam que rodar para o cache acabar com um bitmap de 1 px, e por que o teste "depois da miniatura, não lê a porta" não pega o caso inverso (por isso existe o segundo teste, "sem cache")?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

### Correção das respostas
(sem respostas)

## Tarefa 2.4 — Estilo de Apagar estante e a cor dos alertas do UIKit (2026-10-13)

### O que foi feito
Fechou-se o estilo da tela de apagar estante. O `Paleta.aplicarNoUIKit()` (`Cor.swift`), chamado no `init` de `EstantesApp`, pinta com o `destaque` os botões de todos os alertas e folhas de ação. A segunda folha em `InicioView.swift` passou a dizer a quantidade ("Mover os 6 livros para…", "Mover o livro para…"), reaproveitando `textoDaQuantidade(_:comArtigo:)`. Nenhum teste novo: só mudaram aparência e texto.

### Conceitos envolvidos

**1. Por que o `.tint` do SwiftUI não chegou ao alerta.** O `confirmationDialog` e o `.alert` do SwiftUI, no iOS 16, não são views SwiftUI: o sistema monta um `UIAlertController` e o apresenta por UIKit, em outra hierarquia de views (uma janela/controlador de apresentação próprios). O `.tint` do SwiftUI é um valor de ambiente que desce pela árvore *SwiftUI*; essa árvore não contém o alerta. Quem lê o `tintColor` do alerta é o UIKit, que o resolve subindo pela hierarquia de `UIView`s dele, sem passar pelo ambiente do SwiftUI. Por isso a captura mostrou `#007AFF` (azul do sistema) ao lado do petróleo `#0579B8`.

**2. Proxy de aparência (`UIAppearance`).** `UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self])` devolve um "proxy": você grava nele um valor (`tintColor`) e o UIKit o aplica a toda view daquela classe que, ao entrar numa janela, esteja contida num `UIAlertController`. Detalhes: (a) vale para views criadas *depois* da configuração, então basta chamar uma vez na abertura do app; (b) só funciona com propriedades marcadas `UI_APPEARANCE_SELECTOR`, e `tintColor` é uma delas; (c) o seletor `whenContainedIn` é um filtro por ancestral, não por instância, logo vale para o app inteiro, inclusive o alerta "Nova estante".

**3. Cor dinâmica passa de graça.** `destaque` é um `UIColor(claro:escuro:)`, isto é, uma cor com *provider* que o UIKit resolve a cada mudança de `traitCollection`. Gravada no proxy, ela continua dinâmica: no escuro o botão vira `#AED3FC` sem código extra.

**4. O destrutivo fica vermelho.** O `UIAlertAction` com estilo `.destructive` (vindo do `role: .destructive`) tem cor própria, que ignora o `tintColor`. Por isso a mudança não apaga a semântica "perigo".

**5. Responsabilidade única (Mudança divergente).** A linha estava no `init()` do app, que passaria a mudar por dois motivos: montar dependências e definir aparência. Movida para `Paleta`, junto das cores, o `init` só delega. Quem muda a paleta mexe num lugar só.

### Por que assim
- **Proxy global em vez de corrigir alerta a alerta:** o SwiftUI não oferece um modificador para o `tintColor` desses alertas no iOS 16; o proxy cobre todos e os futuros.
- **Quantidade no título da segunda folha:** na etapa em que o usuário escolhe o destino, a pergunta repete quais livros vão. Confirma o efeito sem custo, e o texto já tinha teste.
- **Destinos só com o nome:** a quantidade em cada botão pesaria a lista, e o Inicio já a mostra.
- **Aspas retas:** preferência do Ricardo; é decisão de gosto, sem custo técnico.
- **Sem linha no Histórico de decisões:** não passa nos três critérios. É surpreendente, mas reverter é apagar uma linha.

### Alternativas descartadas
- **Folha de ação própria com cartões:** teria de reproduzir à mão posição, VoiceOver, foco e comportamento no iPad (popover) para uma confirmação que deve ser rápida e familiar. Custo alto, ganho visual pequeno.
- **Deixar o azul do sistema:** funciona, mas destoa do resto do app.
- **`UIApplication.shared.windows.forEach { $0.tintColor = … }`:** pega só janelas existentes naquele momento e é frágil; o proxy vale para as futuras também.
- **Aspas tipográficas (“ ”):** recusadas pelo Ricardo.

### Padrões e boas práticas
- **Corrigir a documentação junto com o código:** o PLANO dizia que o `.tint` na raiz "chega às folhas"; foi ajustado para "folhas do SwiftUI". Registro errado engana a próxima pessoa que ler.
- **Reaproveitar função já testada** (`textoDaQuantidade`) em vez de duplicar a regra de singular/plural.
- **Quando NÃO usar proxy de aparência:** se só uma tela precisa de outra cor, ele é um efeito global escondido, e quem lê a tela não imagina que a cor vem de outro lugar. Aqui o desejo era justamente global.

### Armadilhas
- Chamar `aplicarNoUIKit()` *depois* de o alerta já ter sido criado não o afeta; por isso o lugar é o `init` do app.
- O proxy não alcança tudo do UIKit: cada classe/propriedade precisa ser `UI_APPEARANCE_SELECTOR`. Se um dia o alerta não mudar de cor, confira primeiro essa condição e a versão do iOS (o comportamento de alertas do SwiftUI mudou entre versões; verifique na CI com Xcode 26 e simulador novo, onde não testamos visualmente).
- Testes unitários não pegam isso: é aparência. A verificação aqui foi pelas capturas (claro, escuro, texto grande).

### Para ir além
- Apple, documentação de `UIAppearance` e `appearance(whenContainedInInstancesOf:)`.
- Apple, Human Interface Guidelines, "Action sheets" e "Alerts".

### Perguntas
1. Com suas palavras: por que o `.tint(...)` aplicado na raiz do SwiftUI não muda a cor dos botões de um `confirmationDialog` no iOS 16, e o que o proxy de aparência faz de diferente?
2. Aplicação: se você quisesse que só os alertas da tela de apagar mudassem de cor, e não os do app todo, o que o `whenContainedIn` deixaria de resolver e que alternativa você consideraria?
3. Raciocínio: se `aplicarNoUIKit()` fosse chamada só quando o usuário abrisse a primeira tela (e não no `init` do app), em que situação a cor sairia errada? E por que o botão "Apagar" continua vermelho mesmo com o proxy valendo?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

### Correção das respostas
(sem respostas)

## Tarefa 2.4 — Fechamento: revisão da branch, extrações e keepalive (2026-10-16)

### O que foi feito
Fechou-se a 2.4 com uma revisão da branch inteira (64 commits, 59 arquivos) por dois revisores em paralelo. Do que apontaram, entraram: `Quantidade.livros` (`Componentes/Quantidade.swift`, com `QuantidadeTests`), o modificador `.alertaDeErro` (`Componentes/AlertaDeErro.swift`), o renome `SecaoDoLivro` → `GrupoDeCampos` (`LivroDetalheViewModel.swift`) e a remoção do token `Espaco.enorme`. O PLANO e o CLAUDE.md foram atualizados (próximo: 2.5). Os 361 testes seguem verdes. Também se conferiu o keepalive do Supabase.

### Conceitos envolvidos

**1. Acoplamento entre telas e a função no lugar errado.** `EstanteView` chamava `InicioView.textoDaQuantidade` só para pluralizar. Uma tela dependia de outra por causa de um utilitário: se o Inicio mudasse ou fosse removido, a Estante quebraria sem motivo de negócio. É o cheiro "Mudança divergente" (uma classe muda por razões que não são dela) e também um começo de dependência circular entre módulos de tela. A saída é mover o utilitário para uma camada comum (`Componentes/`), da qual as duas dependem. Dependências passam a formar um grafo em V (telas -> componentes), não uma fila (Estante -> Inicio).

**2. Regra de três e extração de modificador.** Três cópias do mesmo `.alert` justificavam extrair; a Fase 3 seria a quarta. Como `.alert(isPresented:)` pede `Binding<Bool>` e o ViewModel guarda `String?`, o modificador faz a ponte:

```swift
Binding(get: { mensagem.wrappedValue != nil },
        set: { if !$0 { mensagem.wrappedValue = nil } })
```

O `get` deriva o booleano do opcional; o `set` só reage ao fechar (`false`), limpando a mensagem. Assim há uma única fonte de verdade (a mensagem); o booleano nunca é estado próprio e não pode ficar fora de sincronia. `extension View` com função que devolve `some View` é o jeito idiomático de criar modificadores próprios em SwiftUI (alternativa mais pesada: um tipo `ViewModifier`, útil quando o modificador precisa de `@State` próprio).

**3. Linguagem ubíqua (DDD).** O GLOSSARY lista "seção" como termo a evitar (em Parte e em Prateleira). `SecaoDoLivro` usava a palavra num terceiro sentido, e o leitor teria de adivinhar qual. Nomes de código fazem parte do vocabulário do domínio; renomear é barato (o compilador acha todos os usos), ambiguidade deixada custa a cada leitura.

**4. Código morto detectado por grep.** Para cada `static` em `Componentes/`, procurou-se uso no resto do código; só `Espaco.enorme` não tinha. Técnica simples e eficaz em projeto pequeno. Em projeto grande, o compilador não avisa de símbolos públicos sem uso; existem ferramentas de análise estática para isso (verifique, por exemplo, o Periphery).

**5. Keepalive e o que conta como atividade.** O plano gratuito do Supabase pausa projetos inativos (confira a regra atual na documentação). Só uma requisição que chega ao Postgres conta: um ping sem chave é barrado no gateway (API gateway) antes e não prova nada. Por isso a execução de 15/10 consultou `lexml_livros` de verdade (HTTP 200, 83.612 livros). Outro ponto: o `cron` do GitHub Actions é "melhor esforço": agendado para 12:17 UTC, rodou às 17:05. Atrasos de horas são normais, então o intervalo entre execuções precisa de folga em relação ao limite (aqui, abaixo de 7 dias).

### Por que assim
- **Revisão da branch inteira:** revisar commit a commit não vê o que só aparece no conjunto (duplicação que nasce em três commits distantes, acoplamento entre telas). Dois revisores com focos diferentes (padrões e aderência ao plano) cobrem eixos distintos.
- **Aceitar P1, P2, P4; recusar P3:** generalizar o `switch` carregando/erro/pronto seria generalidade especulativa. O estado "pronto" é diferente em cada tela, então a abstração teria muitos parâmetros e pouca reutilização. Duplicação *aparente* não é duplicação de *conhecimento*.
- **Conferir o achado P5 antes de aceitar:** o revisor disse que `Confirmacao/` e `Scanner/` estavam vazias e fora do git; mas têm `.gitkeep` versionado. Revisor (humano ou modelo) erra; aceitar sem verificar teria criado trabalho inútil.
- **Teste da quantidade só mudou de arquivo:** por isso a contagem ficou em 361. O teste testa a função onde ela agora mora.
- **Só uma linha no Histórico:** o critério é "difícil de reverter". Formulário no `Form` nativo e foto a 1200 px entram (afetam dados e estrutura); o restante se desfaz apagando código.
- **PR pronto, merge por ordem do Ricardo; 2.5 em branch nova a partir do `main`:** mantém PRs revisáveis e evita empilhar trabalho numa branch longa.

### Alternativas descartadas
- Manter `textoDaQuantidade` na `InicioView` e deixá-la `static` pública: resolve a compilação, mas mantém o acoplamento.
- Um componente genérico `EstadoDeTela<Carregando, Erro, Pronto>`: ver P3 acima.
- Colocar a quantidade em `Dominio/`: é texto de apresentação em português, não regra de negócio; o Domínio deve ficar sem formatação de tela.
- Renomear só no código e deixar "seção" nos comentários: foi renomeado em ambos, senão a incoerência volta.

### Padrões e boas práticas
- **Regra de três** (Fowler, *Refactoring*): duplique até a terceira vez, então extraia. Antes disso, você ainda não sabe o que varia. NÃO use quando as cópias parecem iguais mas mudam por razões diferentes.
- **Fonte única de verdade:** derive o que puder (o booleano do alerta) em vez de armazenar.
- **Refatorar com testes verdes:** a suíte de 361 testes é a rede de segurança que permite renomear e mover sem medo.
- **Ceticismo com relatórios automáticos:** verificar a evidência antes de agir.

### Armadilhas
- O `set` do `Binding` derivado é chamado também quando o alerta fecha por outro caminho; se ele limpasse a mensagem sem checar `$0`, abrir o alerta poderia zerá-la.
- Mover um teste de arquivo sem mudar o conteúdo é fácil de esquecer de rodar: confirme que o total de testes não caiu por engano (aqui, a contagem igual vem de um teste removido e um adicionado).
- Cron do GitHub Actions: não confie no horário exato; se o limite do serviço fosse apertado, um atraso poderia estourá-lo.

### Para ir além
- Martin Fowler, *Refactoring* (2ª ed.): "Duplicated Code", "Divergent Change" e a Regra de Três.
- Eric Evans, *Domain-Driven Design*: capítulo sobre Linguagem Ubíqua.
- Documentação do GitHub Actions sobre o evento `schedule` (atrasos e limitações).

### Perguntas
1. Com suas palavras: por que `EstanteView` depender de `InicioView.textoDaQuantidade` era um problema, mesmo compilando e passando nos testes? Que direção as dependências passaram a ter?
2. Aplicação: na Fase 3 surge uma quarta tela com mensagem de erro e uma quinta com dois alertas diferentes. O que `.alertaDeErro` já resolve e o que você precisaria mudar nele (ou não usá-lo) para o segundo caso?
3. Raciocínio: o revisor recusado (P3) propunha unificar o `switch` de estados. Dê um critério para decidir quando uma duplicação deve virar abstração e quando é só coincidência. Aplique-o ao `switch` das telas.

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

(sem respostas)

## Tarefa 2.5 — Categorias: paleta, chips, CorSugerida e telas (2026-10-16)

### O que foi feito
Criou-se o recurso de categorias de ponta a ponta: paleta de 10 cores com tons congelados em hex e teste de contraste, `ChipDeCategoria` e `FluxoDeChips` (layout de fluxo), a regra `CorSugerida` (escrita por você), a porta `quantidadeDeLivrosPorCategoria()`, os ViewModels (`CategoriasViewModel`, `CategoriaFormularioViewModel`, `EscolhaDeCategoriasViewModel`), as telas de gerenciar e de escolha, os chips no Detalhe e na Estante. Fechou-se com revisão em dois eixos (P1–P13, E1–E11) e 400 testes verdes.

### Conceitos envolvidos

**1. Leitura × escrita num subscrito com `default:`.** Em Swift, `dic[chave, default: 0]` é um subscrito com getter e setter.

| Uso | Exemplo | O que acontece |
| --- | --- | --- |
| Leitura | `let uso = usosPorCor[cor, default: 0]` | devolve 0 se a chave não existe; **não grava nada** |
| Escrita | `usosPorCor[c.cor, default: 0] += 1` | lê (0 se ausente), soma, **grava**: a chave nasce aqui |

Por isso, após o primeiro laço de `CorSugerida`, o dicionário só contém cores usadas; as candidatas com 0 uso nunca estão lá, e é o `default:` na leitura que as "enxerga". Também por isso `dic.first` (dicionário não tem ordem garantida; a ordem varia entre execuções) é péssimo ponto de partida, e `keys.first(where:)` pede uma closure, não um valor. O ponto de partida correto é uma sentinela (`Int.max`), de modo que a primeira cor do laço sempre vença.

**2. Por que `<` e não `<=` decide o desempate.** O laço percorre `allCases` na ordem da paleta. Rastreio do teste C2 (Penal amarelo, Civil laranja, Processo e Trabalho vermelho): `[vermelho: 2, laranja: 1, amarelo: 1]`.

```
menorUso = Int.max
vermelho  2 < Int.max  sim -> vermelho (2)
laranja   1 < 2        sim -> laranja  (1)
amarelo   1 < 1        não
verde     0 < 1        sim -> verde    (0)
menta     0 < 0        não   (... demais cores com 0: não)
resultado: verde
```

Com `<=`, cada cor empatada com o mínimo substituiria a anterior, e o resultado seria a **última** com 0 (cinza). O `<` estrito mantém a primeira; o C2 pega essa mutação. Nota do revisor: `min(by:)` devolve o primeiro mínimo na implementação atual, mas a documentação não promete; o laço deixa o desempate explícito e visível, e você optou por mantê-lo.

**3. Função pura e injeção do que varia.** A dúvida "onde encontro as existentes?" tem a resposta: é o parâmetro. Quem chama entrega a lista (testes agora; o ViewModel da folha depois, via `repositorio.categorias()`). Assim a regra fica no Domínio, sem Core Data, e é testável com literais.

**4. Layout customizado (`Layout`, iOS 16).** `FluxoDeChips` implementa `sizeThatFits` e `placeSubviews`. A parte que importa foi isolada numa função pura, `linhas(larguras:espaco:larguraDisponivel:) -> [[Int]]`: algoritmo guloso, O(n), que põe o chip na linha atual se `somaAtual + espaco + largura <= disponível`, senão abre outra linha. Duas bordas importantes: o encaixe exato cabe (`<=`) e um chip maior que a linha vai sozinho (guarda `!atual.isEmpty`; sem ela, abriria-se uma linha vazia). Foram conferidas duas mutações (`>` → `>=` e retirar a guarda), e cada uma morreu num teste diferente. `LazyVGrid` não serve: colunas de largura fixa cortam o texto com Dynamic Type grande.

**5. Cores: congelar e medir contraste.** Cores do sistema (`.systemOrange`...) mudam entre versões do iOS, e o `PaletaTests` roda no iOS 16 do Mac enquanto o `.ipa` roda no iOS 26. Por isso os tons foram copiados em hex. O contraste segue WCAG: razão `(L1 + 0,05) / (L2 + 0,05)` entre luminâncias relativas, mínimo 4,5:1 para texto normal. O teste mistura o véu a 15% sobre o cartão (alfa escrito no próprio teste) e percorre `allCases`. Ele achou um caso real: índigo no escuro dava 4,30:1; escolheu-se #8582FF (4,67) só para o texto.

**6. Teste tautológico × teste de congelamento.** Um teste que recalcula o esperado com a mesma fórmula do código só prova que o código é igual a si mesmo. O teste da paleta compara com hex literais copiados de uma captura aprovada: a fonte é independente (a decisão visual de uma pessoa, registrada). Ele não prova que a cor é bonita; prova que ninguém a muda sem perceber. Seria tautológico se o valor esperado fosse obtido chamando a mesma função/conversão que está sendo testada.

**7. Diagnóstico: causa × mecanismo.** O bug da barra do Detalhe sem fundo ao rolar: sonda temporária que rolava a tela por código, três hipóteses (H1 `.fotoAmpliada`, H2 sem `navigationTitle`, H3 `ScrollView` dentro de `switch`). Tirar `.fotoAmpliada` curou (H1 confirmada), mas a primeira correção (trocar `UIViewControllerRepresentable` por `UIView`) não resolveu: o mecanismo suposto estava errado. A correção real foi a **posição**: o apresentador, que ficava como `.background` da tela inteira (irmão da `ScrollView`, e o SwiftUI usa a primeira `ScrollView` rastreável para o comportamento da barra), foi para dentro do conteúdo. Confirmar a causa não é confirmar o mecanismo; no segundo caso, descreva o que seria visto se estivesse certo e teste isso. (O mecanismo interno exato do SwiftUI é inferência; não está documentado.)

**8. Várias formas de excluir (UX e custo).** Deslizar, menu de contexto e botão na folha de edição chamam a mesma função `pedirExclusao`. Desempenho não muda (modificadores só registram gestos; menu e botão são montados ao usar; `List` é preguiçosa). O custo é de manutenção. Padrão da plataforma (Notas, Lembretes, Mail): um caminho visível mais atalhos. Redundância confunde quando os resultados diferem, quando há botões repetidos à vista, ou quando é incoerente com o resto do app; nenhum caso ocorre aqui.

### Por que assim
- **Paleta de 10 cores com cinza mantido:** o cinza também é o fallback `?? .cinza` da conversão de cor desconhecida; por isso há teste "cor desconhecida vira cinza".
- **Tons congelados, não cores do sistema:** estabilidade entre iOS 16 e iOS 26.
- **`quantidadeDeLivrosPorCategoria() -> [UUID: Int]` com toda categoria presente (0 se vazia):** o chamador não precisa tratar ausência; Core Data conta a relação `livros`.
- **`CategoriaFormularioViewModel` com id fixo desde a abertura:** se o salvamento falhar e o usuário tentar de novo, o mesmo id evita duplicar a categoria (idempotência).
- **Folha sobre folha para "Nova categoria":** exceção justificada; evita perder a escolha em andamento.
- **Folha com OK/Cancelar:** nota de que pode virar "grava a cada toque", como em Lembretes; trade-off entre poder desfazer e menos cliques.
- **`[Categoria].comIds` no Domínio (P9):** conversão de ids em categorias é regra, não tela.
- **P7/P10 anotados:** o OK grava o Livro inteiro lido ao abrir; é limitação conhecida (edição concorrente sobrescreve).
- **P13 recusado:** `.foregroundColor(Cor.perigo)` é proposital, porque `role: .destructive` dá o `systemRed`, que reprova no contraste.

### Alternativas descartadas
- Cores do sistema ao vivo: mudam de versão; quebrariam o contraste sem aviso.
- `LazyVGrid` para chips: corta texto grande.
- `min(by:)` na `CorSugerida`: mais curto, mas o desempate fica implícito (e não documentado).
- Sentinela opcional (`var corMenosUsada: CorCategoria?`): evitaria o `.cinza` inicial, ao custo de desembrulhar depois; ficou a sentinela comentada.
- Só um caminho de exclusão: mais simples, porém menos descobrível (você mesmo não achava como apagar).

### Padrões e boas práticas
- **Função pura no Domínio com dependência por parâmetro** (`CorSugerida`, `linhas`): testável sem infraestrutura. NÃO force quando a regra precisa de estado ou I/O.
- **Teste de mutação manual:** troque um operador e veja se algum teste morre. Se nenhum morre, o teste não protege essa linha.
- **Idempotência por id estável** em operações que podem ser repetidas.
- **Hipótese, previsão, experimento** ao diagnosticar; sonda temporária marcada (`[DEBUG-barra]`) e removida depois.
- **Revisão cética:** o revisor chamou o teste da paleta de tautológico, e a análise mostrou que a fonte é independente (P3 virou renomeação para "congelamento", não remoção).

### Armadilhas
- `dic[k, default: 0]` na leitura não insere; na escrita insere. Confundir os dois leva a achar que o dicionário contém chaves que não tem.
- `Dictionary.first` e `keys` não têm ordem estável: nunca use para desempate.
- `Int.max` como sentinela: nunca some nele (overflow trava o app); aqui só se compara.
- `->` só aparece em tipos de função; `sequence(first:next:)` gera sequências e `min` compara dois valores, e nenhum serve para "achar o menor de uma coleção" com desempate controlado.
- Teste de UI via captura sofre interferência se você usa o simulador durante a captura (contaminou duas).
- Sem XCUITest, o bug da barra não tem teste de regressão; ele só se previne lembrando a lição de posição do apresentador.
- Botão dentro de `NavigationLink` (chips na Estante) pode se comportar diferente entre versões do iOS: conferido à mão no iOS 16; **iOS 26 pendente**.

### Para ir além
- Documentação Apple: protocolo `Layout` (SwiftUI, iOS 16) e `Dictionary.subscript(_:default:)`.
- W3C WCAG 2.x, critério 1.4.3 (Contrast Minimum), com a fórmula de luminância relativa.
- Kent Beck, *Test-Driven Development: By Example*, e o artigo sobre mutation testing (conceito geral; ferramentas variam por linguagem).

### Perguntas
1. Com suas palavras: qual a diferença entre `let uso = dic[cor, default: 0]` e `dic[cor, default: 0] += 1` quanto ao conteúdo do dicionário? Depois do primeiro laço de `CorSugerida`, uma cor sem categorias está no dicionário? Como o segundo laço a trata?
2. Aplicação: no empate, a regra devolve a primeira cor da paleta. Mude `<` para `<=` e diga, para o teste C2 (vermelho 2, laranja 1, amarelo 1), qual cor sairia e por quê. Qual seria o resultado se a paleta fosse percorrida de trás para frente com `<`?
3. Raciocínio: o teste da paleta compara com hex literais congelados. Por que isso não é tautológico? Dê um exemplo de como o mesmo teste ficaria tautológico, e diga o que ele não protege mesmo estando correto.

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

(sem respostas)

---

## Tarefa 2.5b — Conferência do modelo contra livros reais (2026-10-16)

### O que foi feito
Antes de construir a tela do sumário (2.6) e o export JSON v1 (2.8), o modelo `Livro`/`ItemSumario` foi conferido contra as **fotos** de dois livros do conjunto de avaliação (Pontes de Miranda, tomo XLVIII; Lassalle). O Gemini (chat web) fez o OCR em JSON só como ponto de partida. A conferência achou duas lacunas reais: a *matéria* do tomo (`Direito das Obrigações: Contrato coletivo…`) e o *prefaciador*. Resultado: `Colaborador` (`Dominio/Entidades/Colaborador.swift`), `Livro.colaboradores`, persistência em `Conversao.swift`, índice em `IndiceInvertido.swift`, `RascunhoLivro`, formulário e Detalhe; mais a subseção "Contrato de campos" no `docs/PLANO.md`. Testes: 400 → 408.

### Conceitos envolvidos

**1. Conferir o modelo contra a fonte primária.** A pergunta é "o que está impresso que não tem onde morar no meu modelo?". A fonte de verdade é a foto. A saída de outra ferramenta (o JSON do Gemini) é só uma segunda opinião falível: se você conferisse o modelo só contra o JSON, herdaria as omissões dele (e o Gemini perdeu a palavra "Tomo", o "32" da CDU, os assuntos e cortou títulos de § com "…"). Método: tabela *impresso × extrator × nosso campo × situação*.

**2. Lacuna do modelo × omissão do extrator.** São problemas diferentes, com remédios diferentes:
- *Lacuna do modelo*: a informação está na foto e não há campo. Qualquer extrator, perfeito que seja, não consegue entregá-la. Remédio: mudar o esquema (matéria, prefaciador).
- *Omissão do extrator*: há campo, mas o extrator não preencheu. Remédio: prompt e regras (Fase 4), validação (Fase 3). Exemplos: títulos de § cortados, subitens numerados ("1. Conceito. 2. Figurantes…") ausentes (o PLANO já mandava virarem filhos, nível+1, com a mesma página).
Misturar os dois leva a corrigir o lugar errado: mudar o esquema por causa de um bug de OCR, ou "melhorar o prompt" para algo que o esquema nem comporta.

**3. Lista plana com `nivel` × árvore.** O Gemini aninhou em 3 níveis fixos (Parte, Capítulo, §). Nossa lista plana ordenada com `nivel` representa qualquer profundidade (pré-textuais com página romana no nível 1, subitens no nível 4…). A árvore é reconstruível da lista (uma pilha basta, O(n)); o contrário exige travessia. É mais geral e mais simples de persistir e editar.

**4. Serializar uma lista de registros numa única `String` e o separador dentro do dado.** O Core Data aqui guarda `colaboradores` como uma String: uma linha por colaborador, `papel⇥nome`. O problema clássico é o separador aparecer dentro do dado (o OCR pode trazer uma tabulação ou quebra de linha). Há duas saídas:
- *Escaping*: marcar o separador legítimo (`\t` → `\\t`, como CSV com aspas). Preserva o dado exato, mas exige um parser que entenda o escape e é fácil errar.
- *Saneamento*: proibir/trocar o separador no dado antes de gravar. Perde a distinção, mas é trivial e seguro.
Escolheu-se saneamento (`semSeparadores`: tabulação e quebra viram espaço), porque num nome ou papel essa diferença não tem valor. Escaping valeria se o texto pudesse ter significado nesses caracteres (código, parágrafos). Sem uma das duas saídas, o dado volta partido: o colaborador viraria dois, ou o papel entraria no nome. Foi o P1 da revisão, com teste vermelho → verde.
Mais uma armadilha igual à dos autores: `"".components(separatedBy: "\n")` devolve `[""]`, não `[]`. Por isso `lista(_:separador:)` testa `texto.isEmpty` antes. Note também que `colaborador(_:)` corta na **primeira** tabulação, e uma linha sem tabulação vira nome sem papel em vez de sumir (degradação graciosa).
Alternativa estruturada (relação Core Data com entidade própria, ou JSON em campo `Binary`) fica mais "correta", mas custa modelo, migração e mais código para uma lista curta que nunca é consultada por si só.

**5. Texto livre × enum quando o valor bruto é contrato.** `papel` é `String`. Um enum Swift com `rawValue` ("prefacio", "traducao") iria para o JSON v1 e ficaria congelado: renomear ou remover um caso quebraria arquivos exportados antigos, e um papel que não está na lista ("apresentação", "notas de atualização") não teria onde ir. Texto livre guarda "como vem impresso". O preço: sem normalização (o mesmo papel escrito de duas formas) e sem filtro por papel; aceitável porque ninguém filtra por papel aqui. Enum compensa quando o conjunto é fechado e a lógica ramifica no valor.

**6. Teste que não depende de regra alheia ao alvo.** O teste do índice buscava "bastos" e falhou: o índice guarda a forma singular ("basto") por causa da regra `Singular`. A consulta passa pela mesma regra, então a busca real funciona; o teste que inspecionava o índice diretamente é que estava acoplado a um detalhe que não era seu alvo (o alvo é "o nome do colaborador entra no campo `.autores`"). Passou a conferir "aurelio", palavra sem plural. Regra geral: escolha dados de teste que isolem o comportamento testado de regras vizinhas. Já o teste ponta a ponta no `MotorDeBusca` ("wander bastos") cobre o caminho completo, onde a normalização é aplicada nos dois lados.

**7. Genéricos com `inout`.** `apagar<Elemento>` / `mover<Elemento>` recebem `inout [Elemento]`, e servem a autores (`[String]`) e colaboradores (`[Colaborador]`). Evita duplicar a lógica de índices; a limitação é que o helper não sabe nada do elemento (ótimo aqui).

### Por que assim
- **Matéria no `subtitulo`, `parte` = divisão da obra (Q1):** na busca o papel é o mesmo (campo `.subtitulo`, que já inclui `parte`); um campo novo custaria esquema antes de congelar o JSON v1. Juntar em `parte` misturaria dois dados distintos ("Parte Especial" e "Direito das Obrigações").
- **`Colaborador {nome, papel}` separado de `autores` (Q6/Q10):** o cabeçalho ABNT mostra só quem escreveu; um prefaciador ali pareceria coautor.
- **Nome soma no campo `.autores` do BM25F (peso 0,5), papel fora (Q11):** o usuário procura a pessoa como procura um autor; "prefácio" não informa o assunto.
- **Copyright, datas do autor e créditos fora do `Livro`; CDU ao lado da CDD na `FichaExtraida` (Q7):** o modelo não deve virar um espelho de tudo que está impresso, só do que o app usa; mas a ficha guarda todos os códigos CDD/CDU.
- **Autor de item do sumário fica no `titulo` (Q8):** campo a menos, nada se perde.
- **Fontes divergentes (CIP "Lassale" × capa "Lassalle"): transcrever a de maior confiança e devolver a outra como divergência na Fase 3 (Q9):** o Gemini escolheu a grafia da capa **sem avisar**, o que esconde um conflito que o usuário poderia resolver.
- **Contrato de campos no PLANO:** tabela campo × exemplo real + regras contra omissão (página como texto porque pode ser "ix"; CDD/CDU completos; normalização da editora). Vira a base do prompt/esquema da Fase 4.
- **Sem migração do Core Data:** atributo novo editado direto no `.xcdatamodel`, porque não há dados em aparelho; no dia em que houver, isso muda (migração leve com atributo opcional/default).
- **`avaliacao/json_gemini/` fora do Git (Q3):** são dados de avaliação, com possíveis trechos de obras protegidas.

### Alternativas descartadas
- Campo novo `materia`: mesmo papel na busca, mais esquema.
- Juntar colaboradores em `autores`: contamina o cabeçalho ABNT.
- Enum de papéis: rawValue congelado no JSON v1; `[String]` livre: mistura nome e papel numa string.
- Escaping do separador: parser mais complexo para ganho zero aqui.
- Relação Core Data própria para colaboradores: mais custo que o valor.
- Papel sem nome (P3): recusado, ele some sem aviso ao salvar. Isso é uma decisão consciente de que o papel sozinho não identifica ninguém, mas vale saber que há perda silenciosa. `ForEach` por índice (P4) fica como dívida anotada.

### Padrões e boas práticas
- **Conferir esquema contra fonte primária antes de congelar um contrato externo** (JSON v1). Mudar depois custa compatibilidade.
- **Regra explícita contra omissão** no contrato do extrator: dizer ao modelo de IA o que *não* pode cortar ("…", subitens).
- **Degradação graciosa** ao ler formato persistido (linha sem tabulação não some).
- **Normalizar na escrita, ler tolerante** (princípio de Postel, com limites).
- NÃO use string delimitada quando precisar consultar ou filtrar pelo conteúdo no banco, ou quando o dado puder conter o delimitador de forma significativa.

### Armadilhas
- `"".components(separatedBy:)` → `[""]`.
- Separador dentro do dado: o bug só aparece com dado real (OCR), nunca com os exemplos de teste digitados à mão.
- Teste de índice que inspeciona tokens depende de stemming/singularização; prefira palavras neutras ou o teste via motor.
- Confiar na saída do extrator para validar o modelo: herda as omissões dele.
- Rótulo vazio no Detalhe: caiu em "Colaborador" (padrão); convém ter teste para o caso vazio.

### Para ir além
- Martin Kleppmann, *Designing Data-Intensive Applications*, cap. 4 (codificação e evolução de esquemas): compatibilidade para frente e para trás, que é o que o JSON v1 vai exigir.
- RFC 4180 (CSV) para ver o escaping por aspas na prática.
- Documentação Apple, "Core Data Model Versioning and Data Migration".

### Perguntas
1. Com suas palavras: qual a diferença entre uma *lacuna do modelo* e uma *omissão do extrator*? Classifique: (a) o prefaciador do livro de Lassalle não ter campo; (b) o "32" da CDU ter sumido do JSON; (c) os títulos de § cortados com "…".
2. Aplicação: suponha que um papel de colaborador possa conter uma tabulação legítima e que não se possa perder o caractere. Como mudaria o formato de persistência? Descreva o que a gravação e a leitura passariam a fazer.
3. Raciocínio: por que o teste de "bastos" falhou, apesar de a busca funcionar? Diga o que há de errado no teste (não no código) e por que "aurelio" resolve. Que risco continua existindo se só houver o teste de índice, sem o do `MotorDeBusca`?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->

(sem respostas)

---

## Tarefa 2.6 — Sumário manual: RascunhoSumario, folha de edição e o laço do navigationDestination (2026-10-20)

### O que foi feito
Editar o sumário de um livro à mão. No Domínio, `RascunhoSumario` (`Dominio/Regras/RascunhoSumario.swift`) guarda os itens em edição e implementa ida e volta, inserir, apagar, mover, níveis e validação, tudo puro e testado. Em `Apresentacao/Sumario/` ficaram a prévia de 10 itens no Detalhe, a tela "Sumário completo", a folha "Editar sumário" (`EditarSumarioView` + `EditarSumarioViewModel`) e a tela de um item (`EdicaoDoItemView`). A limpeza de texto saiu do `RascunhoLivro` para `Normalizacao.textoLimpo`. Os testes foram de 408 para 449.

### Conceitos envolvidos

**1. Rascunho (draft) como modelo de edição.** O `Livro` guarda `numeracao: String?`; um `TextField` precisa de `String` não opcional. Em vez de espalhar `?? ""` pela tela, o `RascunhoSumario.Item` usa `String` simples e converte nas duas bordas (init e `paraItens()`). Isso transforma a edição em "copiar, mexer, devolver": o Cancelar é grátis (joga o rascunho fora) e o Salvar grava o `Livro` inteiro de uma vez. É o mesmo padrão do `RascunhoLivro`.

**2. Teste de ida e volta (round trip).** `itens → rascunho → itens` deve devolver o mesmo. O T1 achou um defeito real: numeração vazia voltava `""` e não `nil`. Os dois valores "parecem vazios", mas `Equatable` os distingue e a persistência também (um `nil` e um `""` virariam registros diferentes). A correção foi limpar o texto na volta (vazio vira `nil`).

**3. Mutação para provar que um teste vale.** O T5 (limpeza de texto) nasceu verde, o que é suspeito: um teste que nunca falhou pode não testar nada. Trocamos a limpeza por "só tirar as pontas" e 4 testes ficaram vermelhos, incluindo os dois do T5. Isso é *teste de mutação* feito à mão: sabote o código de propósito e veja se algum teste reclama. Se nenhum reclamar, o teste é decoração.

**4. A semântica de `move(fromOffsets:toOffset:)`.** O `.onMove` do SwiftUI entrega um `IndexSet` de origem e um `destino` que conta posições *antes* da retirada: em `[A,B,C]`, mover A para 3 dá `[B,C,A]`, e A para 2 dá `[B,A,C]`. Implementação: retira os itens de trás para frente (para os índices menores não deslocarem), desconta do destino quantos retirados estavam antes dele e insere o bloco. Complexidade O(n·k) para k itens movidos (cada `remove(at:)` é O(n)); com sumários de centenas de itens e k pequeno, irrelevante. Foi escrito à mão porque o `Array.move` é uma extensão do SwiftUI e o Domínio só importa Foundation (regra de camadas).

**5. "Nada é corrigido sozinho" e o teste que o defende.** Nível de item é limitado pelo anterior + 1 (`nivelMaximo`). Se o pai for apagado, o filho pode ficar acima do limite. Corrigir em silêncio seria mexer em dado do usuário sem ele ver. O teste do T4 cobre: item acima do limite *não* é rebaixado por "Nível →". A implementação ingênua `min(nivel + 1, maximo)` passaria nos demais testes e rebaixaria o item sem avisar, porque `min` devolve o máximo, que é menor que o nível atual. Moral: teste a decisão, não só o caminho feliz.

**6. Complexidade escondida em propriedades calculadas (P1).** A versão inicial tinha `erro(item)`, `aviso(item)` e contagem chamando `rascunho.validacao()` (O(n)) para cada linha desenhada. Resultado: O(n²) por desenho, e a cada tecla. A correção: calcular uma vez por mudança, no `didSet` do `@Published`, e guardar num dicionário por id (consulta O(1)). É *memoização com invalidação por escrita*. Cuidado: `didSet` não roda dentro do `init` do mesmo tipo, então o valor inicial precisa de tratamento à parte.

**7. O laço infinito do `navigationDestination(for:)`.** Com a folha aberta, o Detalhe ficava preso em "carregando". Diagnóstico em ordem:

```mermaid
flowchart TD
    A[Detalhe preso em carregando] --> B[Mais espera: nao resolveu, nao e tempo]
    B --> C[Captura equivalente das categorias funciona: defeito na folha nova]
    C --> D[ps: app a 100% de CPU: um laco]
    D --> E[sample: SwiftUI refaz a NavegacaoView sem parar]
    E --> F[Exp 1: sem navigationDestination for UUID a folha abre: causa localizada]
    F --> G[Exp 2: tipo proprio no lugar do UUID: continua em laco, hipotese descartada]
    G --> H[Exp 3: navigationDestination isPresented com State: resolvido, CPU 0%]
```

`ps` mostra se o processo está ocupado (CPU) ou parado (deadlock/espera); `sample` tira amostras da pilha de chamadas e mostra *onde* o tempo vai. Aqui, dentro de uma `NavigationStack` que já tem destinos por tipo, o destino por `UUID` dentro da folha entrou em ciclo de reavaliação. Não sabemos o mecanismo exato (não investigamos o código do SwiftUI, e não vou inventar uma explicação); sabemos o que o experimento mostrou: a forma `isPresented` com um `@State` não tem o problema neste caso. Por isso as linhas viraram `Button` com a seta desenhada: `NavigationLink(value:)` depende do destino registrado por tipo.

**8. Origem preservada.** `OrigemItemSumario` (foto, LexML, Gemini, manual) é gravada no JSON v1. Editar um item *não* o transforma em `manual`: a origem diz de onde o item veio, não quem o mexeu por último. Se virasse `manual`, a avaliação do parser (que compara o que cada fonte extraiu) perderia o rastro. É o `let origem` do `Item`: o compilador impede que a tela a altere.

### Por que assim
- **Folha própria que grava o `Livro` inteiro no Salvar (Q2):** dentro do formulário do livro a tela ficaria enorme; gravar a cada mudança destruiria o Cancelar.
- **Regra pura `RascunhoSumario` no Domínio (Q3):** testável sem simulador, sem SwiftUI; a tela só desenha.
- **Erros só depois de tentar salvar, aviso de página sempre (Q6):** não gritar com o usuário no meio da digitação; aviso não bloqueia.
- **Tela de item empurrada com "Próximo item" (Q9):** campos na própria linha ficam apertados com texto grande (Dynamic Type) e agravam a dívida do `ForEach` por posição.
- **Stepper + deslizar + arrastar (Q10):** três gestos para três necessidades (nível, apagar, ordem).
- **Critério para entrar no Histórico:** difícil de reverter + surpreendente + alternativas reais. Entraram folha própria e origem preservada; ficaram fora quatro decisões por faltar algum critério. Registrar tudo dilui o que importa.
- **Interpolação `Text("\(Text(n).bold()) \(corpo)")` (P8):** `Text + Text` está obsoleto no SDK do iOS 26, e a interpolação existe desde o iOS 14, compilando nos dois Xcodes.
- **Cancelar com mudanças pergunta (P9) e `interactiveDismissDisabled(alterado)`:** descartar trabalho precisa de confirmação; o gesto de arrastar a folha para baixo seria um caminho de perda silenciosa.

### Alternativas descartadas
- Sumário dentro do formulário do livro: ficaria enorme.
- Gravar a cada mudança: perderia o Cancelar.
- Correção automática de níveis: mexe em dados sem o usuário ver.
- Marcar item editado como `manual`: apaga o rastro para a avaliação.
- Campos editáveis na própria linha: apertado e agrava o `ForEach` por posição.
- `.onMove` com edit mode (P3, recusado): o Ricardo conferiu à mão no iOS 16 que funciona sem; fica como risco de plataforma, vale reconferir no iOS 26.
- Reusar `ItemSumario` no rascunho (P11, recusado): a repetição é deliberada, porque o tipo do rascunho tem `String` não opcional e o do domínio tem `String?`; é o mesmo trade-off do `RascunhoLivro`.

### Padrões e boas práticas
- **Draft/Memento leve:** edite uma cópia, confirme ou descarte.
- **Domínio puro, tela burra:** a regra mais difícil (mover, níveis, validação) é a mais testada.
- **TDD em fronteiras aprovadas antes** (tabela "pega / deixa passar").
- **Diagnóstico por experimento único:** um experimento muda uma coisa só; do contrário você não sabe o que resolveu.
- **Refatorar antes de duplicar:** `textoLimpo` foi extraído antes de ser reusado.
- NÃO use memoização em `didSet` quando a conta é barata ou o conjunto é pequeno; aqui valeu porque era O(n) por item desenhado.

### Armadilhas
- `nil` × `""` em campos opcionais: iguais para o olho, diferentes para `Equatable` e para o banco.
- Destino do `onMove` conta antes da retirada: o erro típico é um off-by-one ao mover para baixo.
- `min(nivel + 1, maximo)` rebaixa quando `nivel > maximo`.
- Teste que nasce verde: prove com mutação.
- Tela que "trava": veja a CPU antes de culpar o tempo. 100% é laço; 0% é espera.
- Duas capturas estranhas eram o Ricardo mexendo no simulador ao mesmo tempo; ao depurar interface, elimine variáveis manuais.
- `awk` do macOS conta bytes, não caracteres: "ção" infla o comprimento de linha.
- `didSet` em `@Published` não dispara na inicialização do próprio tipo.

### Para ir além
- Apple, "Managing model data in your app" e a documentação de `NavigationStack` (`navigationDestination(for:destination:)` e `navigationDestination(isPresented:destination:)`), para conferir o comportamento dos destinos.
- Michael Feathers, *Working Effectively with Legacy Code* (testes que descrevem comportamento), e o verbete "Mutation testing" para a ideia geral.
- `man sample` e `man ps` no macOS; Instruments (Time Profiler) é a versão gráfica.

### Perguntas
1. Com suas palavras: por que o Cancelar da folha "Editar sumário" é trivial com um rascunho, e o que se perderia se cada mudança gravasse direto no `Livro`?
2. Aplicação: mova o item A de `[A, B, C, D]` para a posição 3 do `.onMove`, e depois o item D para a posição 0. Escreva o resultado de cada um e explique o desconto `destino - (retirados antes do destino)`. O que mudaria se o `IndexSet` tivesse dois itens?
3. Raciocínio: o Detalhe ficou preso e o experimento 2 (tipo próprio no lugar do `UUID`) continuou em laço. Que hipótese ele eliminou, e por que fazer o experimento 3 junto com o 2 teria estragado a conclusão? Ainda: por que a mutação do T5 (só tirar as pontas) derrubou testes, e o que isso diz sobre um teste que nunca falhou?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->
(sem respostas)

## Tarefa 2.7 — Busca na interface: Decorador + actor, tela própria e duas caças a defeitos do SwiftUI (2026-10-20)

### O que foi feito
Ligamos o motor de busca (2.3) à interface. No Domínio, `BibliotecaIndexada` (`Dominio/CasosDeUso/BibliotecaIndexada.swift`) envolve o repositório e mantém o índice em dia. Em `Apresentacao/Busca/` ficaram a tela Busca (campo próprio, chips, resultados), as telas Filtros e Categorias da busca e o `BuscaViewModel`; `LinhaDoLivro` foi extraída da Estante para ser reusada nos resultados. No caminho, corrigimos um defeito de rolagem que vinha da 2.4/2.5 (Estante e Categorias). Os testes foram de 449 para 490.

### Conceitos envolvidos

**1. Padrão Decorador.** Um Decorador implementa a mesma interface do objeto que envolve, repassa as chamadas e acrescenta comportamento. `BibliotecaIndexada` é um `BibliotecaRepositorio` que contém outro `BibliotecaRepositorio` (a `base`, o Core Data). Para o resto do app ele é indistinguível do repositório comum; só a montagem em `App/Dependencias` sabe da diferença.

```mermaid
flowchart LR
    VM[ViewModels] -->|BibliotecaRepositorio| BI[BibliotecaIndexada]
    BI -->|1. repassa e grava| B[Repositorio Core Data]
    BI -->|2. so se gravou: atualiza| M[MotorDeBusca]
    BV[BuscaViewModel] -->|buscar| BI
```

A ordem importa: grava primeiro, atualiza o índice depois. Se a gravação lançar erro, o `try` aborta antes de tocar o índice, e o índice nunca mostra algo que o banco não tem. O teste 9 prova isso (mutação: atualizar o índice antes de gravar no `apagarLivro` fez o teste falhar).

**2. `actor` e reentrância (o conceito mais traiçoeiro da tarefa).** Um `actor` garante que só um trecho de código mexe no estado dele por vez. Mas essa exclusão só vale *entre* pontos de suspensão: em cada `await`, o actor está livre e outra chamada pode entrar no meio do método (reentrância). Logo, um actor protege a *memória*, não faz uma fila de "métodos inteiros". Consequência concreta aqui:

- `salvar(livro)` faz `await base.salvar` e depois `await atualizarIndice`. Entre os dois, outra chamada pode rodar. O actor não serializa "gravar no banco + atualizar índice" (a P3 da revisão corrigiu um comentário que afirmava o contrário). Hoje isso é seguro porque as telas gravam uma coisa de cada vez; o comentário no código registra o risco.
- A montagem do índice é cara (lê todos os livros e categorias). Se duas buscas chegassem durante ela, cada uma começaria a sua. Solução: a montagem é uma `Task` guardada em `montagem`; quem chega espera a *mesma* (`tarefa.value`).
- Problema novo que isso cria (P1 da revisão): A começa a montagem; um `descartarIndice()` acontece no meio (por exemplo, a releitura de categorias falhou); a montagem antiga termina e grava `motor = montado`, desfazendo o descarte com dados velhos. Correção: um contador `geracao` que sobe a cada montagem e a cada descarte. Quem termina de esperar compara com a geração que viu ao entrar e só grava se for a mesma. É a mesma ideia de *versionamento otimista*: antes de aplicar um resultado atrasado, confirme que o mundo não mudou.

**3. Copy-on-write (COW) e a linha `motor = nil`.** Arrays e dicionários do Swift são tipos-valor com cópia preguiçosa: a cópia só acontece quando alguém *escreve* e há mais de uma referência ao buffer. Em `atualizarIndice`, `guard var atualizado = motor` cria um segundo dono do mesmo buffer. Se mutássemos `atualizado` com `motor` ainda apontando para ele, a primeira escrita copiaria o dicionário do índice inteiro (O(n) por livro salvo). Zerar `motor` antes de mutar deixa um dono só e a mutação ocorre no lugar, em O(1) amortizado por entrada. Troque `n` por 22 fichas e ninguém nota; troque por milhares de livros e passa a importar. O custo é raciocinar sobre uma janela em que `motor == nil` — que só é seguro porque não há `await` entre `motor = nil` e `motor = atualizado` (sem suspensão, ninguém entra).

**4. Casos delicados de consistência.**

| Operação | O que o índice faz | Por quê |
|---|---|---|
| Apagar estante sem destino | lê os livros da estante *antes* e remove cada um do índice | a cascata do banco apaga os livros; depois não há mais como saber quem estava lá |
| Apagar estante com destino | usa as cópias lidas antes, com `estanteId = destino`, e chama `atualizar` | reler depois poderia falhar e acusaria erro numa exclusão que já deu certo |
| Criar, renomear ou apagar categoria | relê a lista de categorias inteira e passa ao motor | o motor precisa da lista completa (nome da categoria é texto buscável) |
| Releitura de categorias falha | descarta o índice (`descartarIndice`) | a gravação deu certo e não vira erro; o índice é que ficou duvidoso, e a próxima busca remonta |
| Índice ainda não montado | nada | a montagem vai ler o banco já gravado |
| Montagem em andamento | espera e aplica por cima | ela pode ter lido o banco antes da gravação; `atualizar`/`remover` repetidos dão o mesmo índice (idempotência) |

A palavra-chave é *idempotência*: aplicar a mesma mudança duas vezes dá o mesmo resultado que uma. É o que torna seguro "aplicar por cima" de uma montagem que talvez já contenha a mudança.

**5. Testes: mutação como prova.** Dos 11 testes da `BibliotecaIndexada`, os que nasceram verdes foram conferidos sabotando o código:

| Mutação | Teste que falhou |
|---|---|
| remover a atualização no `apagarCategoria` | 8 |
| atualizar o índice antes de gravar no `apagarLivro` | 9 |
| não zerar a montagem que falhou | 11 |
| não descartar o índice na releitura de categorias que falha | teste novo da revisão |
| tirar o `formIntersection` de `carregarOpcoes` | 10b |

Um teste proposto, "preparar duas vezes não duplica", foi trocado: o motor guarda os livros por id, então duplicar é impossível e o teste nunca poderia falhar. Teste que não consegue falhar é decoração (mesma lição da 2.6). Dívida assumida: a reentrância (geração, montagem compartilhada) não tem teste, porque exigiria um repositório falso que *pause* a leitura no meio, controlado pelo teste.

**6. Diagnóstico com log: o `.searchable` no iOS 16.** O primeiro desenho usava `.searchable`, a barra de busca nativa. Sintoma: ao empurrar uma tela (Filtros, Detalhe) e voltar, a barra voltava inativa, sem "Cancelar". Em vez de supor, instrumentamos com `os.Logger` e lemos com `log stream --predicate 'subsystem == "com.ricardo.estantes"'`. A evidência: `isSearching = false` aparecia no *mesmo segundo* do empurrão de Filtros (19:39:51, "filtros abertos = true" e "isSearching = false"), e também ao abrir o Detalhe. Conclusão: no iOS 16, empurrar uma tela desliga o `.searchable` da tela raiz.

A sequência de tentativas é uma aula de quando parar:
1. folha Filtros: fechava ao tocar num campo;
2. folha movida para o Inicio: não fechava, mas o OK voltava à grade;
3. tela empurrada: voltava à grade;
4. estado próprio de sessão para lembrar a busca: falhou (barra vazia, e no Detalhe);
5. solução: tela "Busca" própria, com `TextField` + `@FocusState` e botão "Cancelar".

Lição: **remendos sobre um estado do sistema que não controlamos não fecham**. Cada correção mexia nos sintomas de um componente cujo ciclo de vida é decidido pela Apple. Quando a mesma classe de defeito reaparece três vezes, mude a estrutura para não depender dele. Custo: perdemos o visual nativo da barra; ganhamos controle total do estado.

**7. Diagnóstico da rolagem com a skill `/diagnosticar`.** Sintoma: na *primeira* entrada na Estante, rolar não encolhia o título grande e a barra ficava sem fundo; depois de ir ao Detalhe e voltar, funcionava. Um defeito que depende de "primeira vez" costuma ser de *ordem de eventos*, não de lógica.

Primeiro, construir o laço que reproduz: uma captura em DEBUG que empurra a tela 1 s depois de abrir e rola a `UIScrollView` por código 1,5 s depois (o `simctl` não sabe rolar). Um bom laço precisa *distinguir* o vermelho do verde; o controle (com ida e volta ao Detalhe) provou isso:

| Situação | Resultado |
|---|---|
| Estante, 1ª entrada (branch e `main`) | vermelho (título e voltar sobre os livros) |
| Estante com ida e volta ao Detalhe (controle) | verde (prova que o laço distingue) |
| Estante com a correção | verde já na 1ª entrada |
| Categorias, 1ª entrada | vermelho, depois corrigida (verde) |
| Detalhe e Inicio | verdes |

Hipóteses listadas antes de mexer: (1) a lista chega tarde na hierarquia; (2) a troca animada de estado atrapalha; (3) a tarefa de carga roda durante a transição. A 1 foi a confirmada. Causa: o iOS decide *qual rolagem a barra de navegação acompanha* quando a tela aparece, procurando a `UIScrollView` na hierarquia naquele momento. A `ScrollView` da Estante só surgia depois do estado "carregando", então no primeiro quadro não havia nada para acompanhar. Correção: a Estante passa a ter uma `ScrollView` desde o primeiro quadro, com os estados dentro (um `GeometryReader` + `minHeight` para o aviso de vazio ocupar a tela); a Categorias mantém a `List` sempre presente e põe carregando/vazio/erro em `.overlay`.

Dois fatos de método: o defeito vinha da 2.4/2.5 (vermelho também no `main`), então não era regressão desta tarefa; e uma tentativa intermediária (trocar por `VStack` no Inicio) foi revertida porque o Ricardo viu o defeito em outras telas, que era este defeito antigo, não a mudança. Depois da correção, a `VStack` voltou (Q29) e funcionou. Aprender: ao reverter, confirme se a mudança era mesmo a causa; senão você joga fora uma ideia boa por culpa de outro bug. Não há teste de regressão, porque só um teste de interface (XCUITest) alcança o comportamento da barra de navegação.

**8. Concorrência na tela: cancelamento cooperativo.** `.task(id: chave)` cancela a tarefa anterior quando a chave muda (digitou mais uma letra). Cancelar em Swift é *cooperativo*: só marca a tarefa; quem está rodando precisa olhar. Pontos concretos:
- `guard !Task.isCancelled` depois do `await` da busca: o actor termina o que começou, então a resposta velha chega mesmo assim, e sem o guard ela sobrescreveria a nova (corrida clássica de "resposta atrasada").
- P5: `try? await Task.sleep` (o atraso de digitação, *debounce*) engolia o `CancellationError`, e a busca seguia como se nada tivesse acontecido. Trocado por `do/catch` que sai.
- P12: o `aoVoltar` chamava `buscar()` em paralelo com a `.task(id:)`. Duas buscas ao mesmo tempo, sem ordem garantida. Agora `pedirNovaBusca()` só sobe uma `versao` que faz parte da chave, e existe um único caminho que dispara a busca.
- P8: `.nadaEncontrado(texto:)` guarda o texto *buscado*, não o que está no campo agora; senão a mensagem "Nada encontrado para X" mudaria enquanto você digita, antes de haver outro resultado.

**9. Interface.** Botão no Inicio com aparência de barra, numa `VStack` acima da lista (com `safeAreaInset` o título grande passava por cima). Tela Busca com cabeçalho fixo em `.ultraThinMaterial` (campo + chips). Chips de filtro: desmarcado `Cor.campo` (`tertiarySystemFill`), marcado `superficie`. Filtros: anos só com 4 dígitos, via `BuscaViewModel.ano(deTexto:)` (função pura, testável); faixa invertida (2020–2010) esconde o botão de voltar até corrigir. Categorias: várias ao mesmo tempo, com semântica OU; usamos uma tela empurrada, não um `Menu`, porque o `Menu` do iOS 16 fecha a cada toque e `menuActionDismissBehavior` é do 16.4, que o Xcode 14.2 não compila (a regra dos dois Xcodes de novo). A `LinhaDoLivro` foi extraída da Estante e as capturas antes e depois foram comparadas pixel a pixel com PIL: idênticas, o que prova que a extração foi só refatoração. `LinhaDoResultado.item`/`.lugar` mostram item e lugar em duas linhas.

### Por que assim
- **Decorador em vez de cada ViewModel avisar o índice:** são 6+ lugares que gravam; esquecer um deixa o índice mentindo, e o erro só aparece como "busca não acha o livro novo". Centralizar na borda do repositório torna a invariante "índice = banco" responsabilidade de um só arquivo.
- **`actor` em vez de classe `@MainActor`:** a montagem e a busca (tokenizar, BM25F) são trabalho de CPU que não deve travar a interface; um `@MainActor` rodaria tudo na thread principal.
- **Tela Busca própria em vez de `.searchable`:** ver conceito 6; controle do estado vale mais que o visual nativo.
- **Editora fora da barra de busca:** ruído. "Livraria Freitas Bastos" casaria com o prefaciador Bastos do Lassalle, e não temos medida para o peso certo (só 4 de 22 fichas têm editora). Sem dado, não se calibra; melhor não incluir.
- **Apagar estante lê os livros antes:** ver tabela do conceito 4.
- **Várias categorias com OU:** quem marca "Civil" e "Penal" quer ver livros de qualquer uma; E daria quase sempre lista vazia.

### Alternativas descartadas
- Cada ViewModel avisar o índice: 6+ lugares, fácil esquecer.
- Remontar o índice a cada busca: custo O(todos os livros) por tecla.
- Classe `@MainActor`: bloqueia a interface durante montagem/busca.
- Porta própria só para a busca (P4, recusado): haveria um único uso; abstrair com um implementador só é custo sem benefício.
- Esconder o botão voltar com faixa inválida (P11, recusado pela revisão): foi pedido do Ricardo, então fica; a revisão apontou que esconder o voltar é fora do padrão da plataforma.
- `Menu` para categorias: fecha a cada toque no iOS 16.
- `.searchable` com remendos: cinco tentativas, nenhuma fechou.

### Padrões e boas práticas
- **Decorador:** acrescenta comportamento sem alterar quem usa nem o decorado. NÃO use quando o comportamento novo precisa de uma interface diferente (aí é um serviço à parte) ou quando há um único chamador (um método direto basta).
- **Invalidar por geração/versão:** serve para qualquer resultado assíncrono que possa chegar atrasado.
- **Um único caminho para disparar a busca** (a `chave` da `.task(id:)`): reduz as formas de entrar em estado inconsistente.
- **Diagnóstico: laço antes de hipótese de correção.** Primeiro um jeito de reproduzir e distinguir; depois mudanças, uma por vez.
- **Refatoração provada por captura idêntica** (extração da `LinhaDoLivro`).
- **Dívida declarada:** P10 (`LinhaDoLivro` acoplada a funções estáticas de ViewModels) e os testes de reentrância ficaram anotados, não escondidos.

### Armadilhas
- Achar que `actor` serializa métodos inteiros. Só serializa trechos sem `await`.
- Dois donos de um dicionário grande (COW) fazem uma mutação virar cópia completa; olhe para isso quando uma operação "simples" ficar lenta.
- `try?` em torno de `Task.sleep` ou de qualquer `await` cancelável: some o cancelamento.
- Aplicar a resposta de uma tarefa cancelada: confira `Task.isCancelled` depois do `await`.
- A tela só "funciona na segunda vez": desconfie de ordem de criação da hierarquia (`ScrollView` que aparece tarde), não de lógica.
- Remendar um componente do sistema repetidamente: se a terceira correção não fecha, mude a estrutura.
- `menuActionDismissBehavior` e outras APIs 16.4+: compilam na CI (Xcode 26), mas quebram o Xcode 14.2 local.
- Testes que não conseguem falhar (o "preparar duas vezes").

### Para ir além
- Swift Evolution SE-0306 (Actors), seção sobre reentrância, e *The Swift Programming Language*, capítulo "Concurrency".
- Gamma, Helm, Johnson, Vlissides, *Design Patterns* (Decorator).
- Documentação Apple: `Task.isCancelled`, `Task.checkCancellation()` e "Cooperative cancellation" no capítulo de concorrência.

### Perguntas
1. Com suas palavras: o que a reentrância de um `actor` significa, e por que ela obrigou a montagem do índice a ser uma `Task` guardada e a ter um contador `geracao`? Descreva a sequência de eventos que o contador impede.
2. Aplicação: hoje a `BibliotecaIndexada.apagarEstante` com destino reaproveita as cópias lidas antes. Se o app passasse a permitir que o usuário edite um livro *enquanto* a estante é apagada, que problema novo poderia aparecer no índice? O que você faria?
3. Raciocínio: no diagnóstico da rolagem, o controle "ida e volta ao Detalhe" deu verde. Por que um controle assim é indispensável antes de aceitar que a correção funcionou? E por que, na tela Busca, o `guard !Task.isCancelled` é necessário mesmo com `.task(id:)` cancelando a tarefa anterior?

### Minhas respostas
<!-- Ricardo responde aqui por escrito. O teacher corrige na próxima chamada. -->
