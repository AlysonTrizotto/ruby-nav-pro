<<<<<<< HEAD
# Ruby Nav - Context-Aware Ruby Navigation

Extensão VS Code que fornece navegação inteligente para código Ruby/Rails com **análise de contexto semântico**.

## 🎯 Características Principais

### Contexto Inteligente
- **Navegação contextual**: Entende a diferença entre `User.save` e `Product.save`
- **Análise de receiver**: Sabe quando você está chamando `obj.metodo` vs definindo `def metodo`
- **Detecção de padrões Rails**: Reconhece `belongs_to`, `scope`, `validates`, etc.

### Funcionalidades
- **Go to Definition** (Ctrl+D): Vai para a definição correta com base no contexto
- **Find References** (Ctrl+Shift+D): Encontra referências relevantes, não apenas texto igual
- **Debug Context** (Novo): Mostra o contexto analisado para debugging

## 🧠 Como o Contexto Funciona

### Antes (Ctrl+F simples):
```ruby
user.save    # Encontrava TODOS os 'save' do projeto
product.save # Mesma coisa - sem distinção!
```

### Depois (Com contexto):
```ruby
user.save    # Vai direto para User#save
product.save # Vai direto para Product#save
```

### Exemplos de Contexto Detectado:
- **Chamada de método**: `obj.method` → Procura `def method` na classe do `obj`
- **Definição de classe**: `class User` → Entende que é uma definição
- **Include/Extend**: `include Module` → Sabe que é um módulo sendo incluído
- **Associações Rails**: `belongs_to :user` → Entende o contexto ActiveRecord

## 🚀 Uso

1. **Go to Definition**: Clique em um símbolo e pressione `Ctrl+D`
2. **Find References**: Clique em um símbolo e pressione `Ctrl+Shift+D`
3. **Debug Context**: Use o comando "Ruby: Debug Context" para ver o que foi detectado

## 🔧 Tecnologia

- **Parser AST**: Usa Ripper (parser oficial do Ruby)
- **Indexação inteligente**: Analisa contexto de namespaces e escopos
- **Comunicação**: JSON-RPC entre cliente VS Code e servidor Ruby
- **Performance**: Indexação em background sem bloquear o editor

## 📋 Requisitos

- VS Code >= 1.70.0
- Ruby instalado no sistema
- Projeto Ruby/Rails para navegação

---

**Diferença principal**: Enquanto outras extensões fazem busca textual (Ctrl+F), esta entende **semanticamente** o que você está procurando.
=======
Ruby Nav

This package implements go-to-definition and find-references using Ripper AST scanning, optimized for large monolith Rails projects. It indexes in background, provides progress updates and supports QuickPick to choose among multiple targets.
>>>>>>> cb345dd5fd9a99a68d4978b36643c4b851446380
