# Ruby Navigation (AST-based)

Navegação rápida e confiável em grandes monolitos Ruby on Rails usando análise de AST com Ripper.  
Encontre **definições** e **referências** de classes, métodos, controllers e rotas sem depender do autoload do Rails ou de um LSP pesado.

---

## ✨ Funcionalidades

- **Go to Definition (Manual)** (`Ctrl+D`)
  - Vai direto para a definição da classe ou método sob o cursor.
  - O mesmo fluxo alimenta **F12** (Go to Definition nativo), quando o RubyNav devolve um resultado.
  - Entende `controller#action` e resolve para o método correto no controller.
  - Usa índices em memória baseados em AST, otimizados para monolitos grandes.

- **Show References** (`Ctrl+Shift+D`)
  - Lista todas as ocorrências relevantes do símbolo:
    - Chamadas de método (`Foo.bar`, `Sales::RoutesBasis.where(...)`).
    - Referências a constantes (fallback por texto em arquivos relacionados).
    - Rotas que apontam para um `controller#action`.
  - Interface agrupada:
    - Por arquivo (caminho relativo).
    - E dentro do arquivo, por classe/método.
  - Visual limpo, com separadores de grupos, para navegar como em um “grep inteligente”.
  - **Shift+F12** (Find All References nativo) usa o mesmo índice quando o RubyNav responde.

- **Suporte a Rails**
  - Parser simples de `config/routes.rb`, incluindo entre outros:
    - `namespace` (e `namespace :x, path: 'y'` para o prefixo URL),
    - `scope` com `module:` / `path:`,
    - `resources` com REST, `path:`, `only:`, `except:` (também com `… do` + `only`/`except` em linha),
    - `member` / rotas com `get :action` dentro de `resources`,
    - `get/post/...` com `to: 'controller#action'`, `match` com `via:`.
  - Mapeia rotas para `Controller#action` e exibe essas rotas como referências.

- **Indexação incremental em background**
  - Assim que um workspace Ruby é aberto:
    - Um servidor Ruby é iniciado em segundo plano (`extension.js` faz `spawn` de `ruby server/server.rb`).
    - Ficheiros **`**/*.rb`** e **`**/*.erb`** (exceto `spec`, `test`, `vendor`, `node_modules`) são indexados.
    - Em **ERB**, só o Ruby dentro de `<% … %>`, `<%= … %>`, `<%- … %>` (etc.) é analisado pelo Ripper; HTML à volta não entra no AST.
  - Barra de status:
    - `RubyNav: indexando...` com progresso em `%`.
    - `RubyNav pronto` ao finalizar.

- **Hot-reload automático** ✨
  - Detecta automaticamente quando você:
    - Cria ou altera um arquivo `.rb` ou `.erb`
    - Deleta um arquivo `.rb` ou `.erb`
  - Re-indexa apenas o arquivo modificado (incremental)
  - Não precisa reiniciar o editor!
  - Comando manual disponível: `Ruby: Re-indexar Workspace` para re-indexação completa
---

## 🧠 Como funciona

### Arquitetura

1. **`extension.js`** (entrada declarada em `package.json` como `main`) ativa-se com ficheiros Ruby e regista comandos e atalhos.
2. Arranca um processo **`ruby`** com `server/server.rb` (cwd = raiz do workspace), que carrega os módulos em `server/ruby_nav/` (Ripper, índice, comandos).
3. Comunicação **JSON, uma linha por mensagem**, em `stdin` / `stdout` entre o editor e o processo Ruby.

### O que o servidor faz

- Usa **Ripper** para gerar AST dos ficheiros **`.rb`** e dos **fragmentos Ruby em `.erb`**.
- Extrai:
  - Definições de classes, módulos e métodos.
  - Chamadas de métodos com receiver (`Foo.bar`, `Namespace::Foo.baz`).
  - Métodos de instância em controllers (para `controller#action`).
- Analisa `config/routes.rb` com um **parser próprio, limitado** (ver limitações), preenchendo estruturas como `ROUTE_BY_ACTION`.
- Mantém índices em memória para responder a `definition` e `references`.

### O que o cliente envia (exemplos)

- `{ "command": "definition", "word", "receiver", "file", "line", "col", "id": "…" }`
- `{ "command": "references", "symbol", "receiver", "file", "line", "col", "id": "…" }`

Os resultados são priorizados por **contexto** (por exemplo `app/controllers` vs. `lib/`) quando faz sentido.

### Ficheiros `.erb`

As extensões `.erb` partilham o `language id` Ruby para **gramática / cor**.  
**Indexação:** o servidor extrai o Ruby das tags (`<%`, `<%=`, `<%-`, …), corre o Ripper em cada fragmento e mapeia **linha/coluna** de volta ao ficheiro `.erb`. HTML fora das tags não é AST.

**Variáveis locais em ERB:** o “go to definition” de locais (`:var_ref`) continua **desativado** em `.erb` (o Ripper do ficheiro completo não corresponde ao template).

---

## ⌨️ Atalhos de teclado

- **Go to Definition (Manual)**  
  `Ctrl+D` (quando o cursor está sobre um símbolo Ruby)

- **Show References**  
  `Ctrl+Shift+D`

Você também encontra esses comandos na Command Palette (`Ctrl+Shift+P`):

- `Ruby: Go to Definition (Manual)`
- `Ruby: Show References`
- `Ruby: Re-indexar Workspace` (força re-indexação completa)

**Nota:** os comandos acima e os atalhos **Ctrl+D** / **Ctrl+Shift+D** continuam disponíveis. Além disso, o editor pode usar **F12** (Go to Definition) e **Shift+F12** (Find All References) quando o RubyNav é o provider que devolve resultados — o mesmo protocolo ao servidor Ruby.

---

## ✅ Requisitos

- **VS Code / Windsurf** `>= 1.85.0`
- **Ruby** `>= 3.x` disponível no `PATH` do processo do editor  
  (a extensão executa `ruby server/server.rb` com o diretório de trabalho na raiz do workspace).
- Projeto Ruby / Rails aberto como **pasta** (não apenas arquivo solto), para que:
  - O servidor use a raiz correta.
  - `config/routes.rb` e `app/**` sejam encontrados.

---

## 🚀 Uso

1. Abra o seu monolito Ruby/Rails como pasta no editor.
2. Abra qualquer arquivo `.rb`.
3. Espere a barra de status mostrar:
   - `RubyNav: indexando...` → depois `RubyNav pronto`.
4. Posicione o cursor:
   - Em uma classe, módulo ou método → `Ctrl+D` para ir para a definição.
   - Em um símbolo (classe/método/`controller#action`) → `Ctrl+Shift+D` para ver as referências.
5. Na lista de referências:
   - Itens são agrupados por **arquivo** e por **classe/método**.
   - Escolha uma ocorrência para navegar direto para a linha.

---

## 🧩 Casos de uso típicos

- **Controllers e rotas**
  - De uma linha em `config/routes.rb` com `to: "reservations#cancel"`:
    - `Ctrl+D` em `reservations#cancel` abre `ReservationsController#cancel`.
    - `Ctrl+Shift+D` mostra todas as rotas configuradas para essa action.

- **Models / Services grandes**
  - Em uma classe como `Sales::RoutesBasis`:
    - `Ctrl+Shift+D` lista:
      - Chamadas como `Sales::RoutesBasis.where(...)`.
      - Outras menções a `RoutesBasis` em arquivos relacionados.

---

## ⚠️ Limitações conhecidas

- Não é um LSP completo:
  - Focado em navegação (defs + refs).
  - Não oferece code completion, linting ou refactoring.
- **Templates `.erb`:** além de cor/gramática, o **índice** inclui chamadas e defs nos tags Ruby; **não** há `path_to_const` nem `class|module` por ficheiro como em `.rb`. Chamadas encadeadas muito aninhadas podem perder alguns passos.
- Não entende todos os metaprogramming avançados:
  - Macros ou meta-definições muito dinâmicas podem não ser indexadas.
- O parser de rotas é propositalmente simples:
  - Cobre um subconjunto de `config/routes.rb` (`namespace`, `scope` com `module`/`path`, `resources`, rotas HTTP com `to:`, `match` com `via:`, etc.).
  - Não cobre toda a DSL do Rails (engines isolados, `constraints` complexos, `draw`, rotas geradas dinamicamente, etc.); nesses casos as rotas podem não aparecer nas referências.

---

## 🛠️ Feedback e contribuições

Encontrou um caso em que a navegação não funciona bem no seu monolito?

- Abra uma issue no repositório:
  - Informe:
    - Trecho de código (classe/método).
    - O que você fez (`Ctrl+D` / `Ctrl+Shift+D` em qual símbolo).
    - O que aconteceu vs. o que esperava.
- Sugestões de novas heurísticas (ex.: associações ActiveRecord, concerns, engines) são muito bem-vindas.

---

Obrigado por usar o Ruby Navigation em seus monolitos Rails!  
A ideia é ser uma ferramenta leve, previsível e útil no dia a dia, sem substituir seu LSP favorito, mas sim complementar quando a navegação padrão não acompanha o tamanho do projeto.