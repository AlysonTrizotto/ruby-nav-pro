# Ruby Navigation (AST-based)

Navegação rápida e confiável em grandes monolitos Ruby on Rails usando análise de AST com Ripper.  
Encontre **definições** e **referências** de classes, métodos, controllers e rotas sem depender do autoload do Rails ou de um LSP pesado.

---

## ✨ Funcionalidades

- **Go to Definition (Manual)** (`Ctrl+D`)
  - Vai direto para a definição da classe ou método sob o cursor.
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

- **Suporte a Rails**
  - Parser simples de `config/routes.rb`:
    - `namespace`, `scope module/path`, `resources`, `member do`, `get/post/put/patch/delete`, `match`.
  - Mapeia rotas para `Controller#action` e exibe essas rotas como referências.

- **Indexação incremental em background**
  - Assim que um workspace Ruby é aberto:
    - Um servidor Ruby é iniciado em segundo plano.
    - Todos os arquivos `**/*.rb` (exceto `spec`, `test`, `vendor`, `node_modules`) são indexados.
  - Barra de status:
    - `RubyNav: indexando...` com progresso em `%`.
    - `RubyNav pronto` ao finalizar.

- **Hot-reload automático** ✨
  - Detecta automaticamente quando você:
    - Cria um novo arquivo `.rb`
    - Modifica um arquivo existente
    - Deleta um arquivo
  - Re-indexa apenas o arquivo modificado (incremental)
  - Não precisa reiniciar o editor!
  - Comando manual disponível: `Ruby: Re-indexar Workspace` para re-indexação completa
---

## 🧠 Como funciona

Por baixo dos panos:

- Um servidor Ruby (via `server/server.rb`) é iniciado quando a extensão ativa.
- Ele:
  - Usa **Ripper** para gerar AST dos arquivos Ruby.
  - Extrai:
    - Definições de classes, módulos e métodos.
    - Chamadas de métodos com receiver (`Foo.bar`, `Namespace::Foo.baz`).
    - Métodos de instância em controllers (para `controller#action`).
  - Analisa `config/routes.rb` para criar índices de `ROUTES` e `ROUTE_BY_ACTION`.
  - Mantém índices globais em memória para responder rápido a:
    - `definition`
    - `references`

Do lado do editor:

- A extensão envia comandos simples via `stdin/stdout` para o servidor em JSON:
  - `{ command: "definition", word, file, line, col }`
  - `{ command: "references", symbol, file }`
- Recebe resultados já priorizados por **contexto**:
  - Arquivos em `app/controllers`, `app/models`, etc. são priorizados quando o comando parte desse mesmo contexto.

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

---

## ✅ Requisitos

- **VS Code / Windsurf** `>= 1.85.0`
- **Ruby** `>= 3.x` disponível no `PATH` do editor  
  (a extensão chama `ruby server/server.rb --index` no workspace)
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
- Não entende todos os metaprogramming avançados:
  - Macros ou meta-definições muito dinâmicas podem não ser indexadas.
- O parser de rotas é propositalmente simples:
  - Cobrirá a maioria dos casos comuns de `routes.rb`, mas não 100% de DSLs customizadas.

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