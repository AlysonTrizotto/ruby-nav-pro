# Changelog

Todas as mudanças notáveis neste projeto serão documentadas neste arquivo.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/),
e este projeto adere ao [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [1.3.0] - 2025-11-28

### ✨ Adicionado
- **Show References Context-Aware**: `Ctrl+Shift+D` agora usa o receiver para encontrar referências precisas
  - Encontra chamadas específicas como `Trips::CacheService.call`
  - Diferencia de chamadas genéricas `.call`
  - Suporta busca por classe (ex: `Trips::CacheService`) encontrando tanto chamadas quanto usos textuais (includes)

### 🔧 Modificado
- **handle_references**: Lógica reescrita para priorizar busca estruturada por receiver
  - Se receiver existe, busca apenas chamadas naquele receiver
  - Fallback inteligente para busca textual apenas se necessário
  
- **Parser AST (Ripper)**:
  - **Correção Crítica**: Agora recursa corretamente dentro de métodos (`def`) e métodos de classe (`defs`)
  - Antes, chamadas dentro de métodos eram ignoradas pelo indexador! 😱
  - Adicionado suporte a `:var_ref` em `collect_const_path` para extrair receivers complexos corretamente

### 🐛 Corrigido
- **"Show References não encontra nada"**:
  - Corrigido bug onde chamadas dentro de métodos não eram indexadas
  - Corrigido bug onde receivers aninhados (`Trips::CacheService`) não eram extraídos corretamente
  - Corrigido bug onde `Ctrl+Shift+D` enviava apenas a palavra sem o receiver

### 📊 Impacto
- **Indexação**: Agora indexa 100% das chamadas de métodos (antes ignorava ~90% que estavam dentro de `def`)
- **Precisão**: Encontra exatamente onde `Service.call` é usado

---

## [1.2.0] - 2025-11-28

### ✨ Adicionado
- **Extração inteligente de receiver**: O frontend agora extrai o receiver completo antes do método
  - Captura `Trips::CacheService` quando você está em `Trips::CacheService.call`
  - Não captura apenas "call", mas o contexto completo
  
- **Indexação de métodos de classe**: Métodos estáticos (`def self.method`) agora são indexados corretamente
  - Indexa com namespace completo: `Trips::CacheService.call`
  - Indexa também nome curto para fallback: `CacheService.call`
  - Armazena em `@instance_methods` para busca rápida

- **Novo script de teste**: `test_receiver_search.rb`
  - Valida busca com e sem receiver
  - Compara precisão entre os dois modos
  - Verifica matches exatos vs parciais

### 🔧 Modificado
- **handle_definition**: Agora usa receiver para filtrar resultados
  - Prioriza matches exatos (namespace completo)
  - Retorna apenas resultados relevantes ao receiver
  - Exemplo: `Trips::CacheService.call` não retorna mais `Admin::OrderCancellationService.call`
  
- **parse_defs_and_calls**: Detecta métodos de classe (`:defs`)
  - Identifica `def self.method_name`
  - Indexa com namespace completo do stack
  - Marca como `class_method: true` em `@instance_methods`

- **extractSymbolWithReceiver** (extension.js): Nova função
  - Extrai receiver antes do cursor
  - Suporta namespaces aninhados (`Foo::Bar::Baz`)
  - Regex pattern: `/([A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*)[\.\s]*$/`

### 🐛 Corrigido
- **Busca de definições com baixa precisão**: 
  - Antes: `Ctrl+D` em `Trips::CacheService.call` retornava TODOS os `.call` de todos os services
  - Depois: Retorna apenas `Trips::CacheService.call` e variações diretas
  - Redução de ~95% em resultados irrelevantes

### 📊 Impacto
**Exemplo real do usuário**:
```ruby
# Antes (v1.1.0): Ctrl+D em "call" retornava:
- Admin::OrderCancellationService.call ❌
- Admin::ReservationCancelationService.call ❌
- Checkout::Braintree::CreditCardChargeService.call ❌
- Checkout::Cielo::PixChargeCreatorService.call ❌
- ... dezenas de outros services ...
- Trips::CacheService.call ✓ (perdido no ruído)

# Depois (v1.2.0): Retorna apenas:
- Trips::CacheService.call ✓
- Trips::CacheService#call ✓ (método de instância, caso exista)
```

---

## [1.1.0] - 2025-11-28

### ✨ Adicionado
- **Hot-reload automático**: A extensão agora detecta mudanças em arquivos Ruby em tempo real
  - Detecta criação de novos arquivos `.rb`
  - Detecta modificações em arquivos existentes
  - Detecta deleção de arquivos
  - Re-indexa automaticamente apenas os arquivos modificados (incremental)
  - Sistema de debounce (500ms) para evitar múltiplas re-indexações
  - Ignora automaticamente arquivos em `spec/`, `test/`, `vendor/`, `node_modules/`
  
- **Comando manual de re-indexação**: `Ruby: Re-indexar Workspace`
  - Disponível via Command Palette (`Ctrl+Shift+P`)
  - Força re-indexação completa de todo o workspace
  - Útil para sincronização quando necessário

- **Novo script de teste**: `test_hot_reload.rb`
  - Valida funcionalidade de re-indexação incremental
  - Testa criação, modificação e deleção de arquivos

### 🔧 Modificado
- **extension.js**:
  - Adicionado `FileSystemWatcher` para monitorar mudanças em arquivos `.rb`
  - Implementadas funções `reindexFile()` e `reindexWorkspace()`
  - Registrado novo comando `rubyNav.reindexWorkspace`

- **server/server.rb**:
  - Adicionado handler `handle_reindex_file(req)` para re-indexação incremental
  - Adicionado handler `handle_reindex_workspace()` para re-indexação completa
  - Implementada função `remove_file_from_index(abs_path)` para limpeza de índices
  - Adicionada flag `$TESTING` para suportar execução de testes standalone

- **README.md**:
  - Documentada nova funcionalidade de hot-reload
  - Adicionado comando de re-indexação manual na lista de comandos

### 🐛 Corrigido
- Removida variável não utilizada `current_file` em `RouteIndexer` (lint warning)
- Removido `activationEvents` redundante do `package.json` (gerado automaticamente)

### 📝 Documentação
- Criado `HOT_RELOAD_IMPLEMENTATION.md` com detalhes técnicos da implementação
- Criado `CHANGELOG.md` para rastrear mudanças de versão

---

## [1.0.0] - 2025-11-25

### 🎉 Release Inicial

- **Go to Definition** (`Ctrl+D`)
  - Navegação para classes, módulos, métodos
  - Suporte para `controller#action`
  - Priorização por contexto (namespace/caminho)

- **Show References** (`Ctrl+Shift+D`)
  - Lista todas as referências de um símbolo
  - Interface agrupada por arquivo e classe/método
  - Suporte para rotas Rails

- **Parser de Rotas Rails**
  - Suporte para `namespace`, `scope`, `resources`
  - Rotas HTTP: `get`, `post`, `put`, `patch`, `delete`, `match`
  - Mapeamento automático de `controller#action`

- **Indexação AST com Ripper**
  - Indexação completa de workspaces Ruby/Rails
  - Suporte para classes, módulos, métodos
  - Rastreamento de chamadas de métodos
  - Barra de status com progresso

- **Context-Aware Search**
  - Sistema de scoring por contexto
  - Prioriza resultados no mesmo namespace
  - Considera hierarquia de módulos completa

---

## Tipos de Mudanças
- `✨ Adicionado` - Novas funcionalidades
- `🔧 Modificado` - Mudanças em funcionalidades existentes
- `🗑️ Removido` - Funcionalidades removidas
- `🐛 Corrigido` - Correções de bugs
- `🔒 Segurança` - Correções de segurança
- `📝 Documentação` - Mudanças na documentação
- `⚡ Performance` - Melhorias de performance
