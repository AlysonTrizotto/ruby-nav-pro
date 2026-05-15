#!/usr/bin/env ruby

# Teste para validar Show References com receiver

$TESTING = true
require_relative "../server/server"

# Limpar índices
@index = Hash.new { |h, k| h[k] = [] }
@const_map = {}
@relations = Hash.new { |h, k| h[k] = Set.new }
@references = Hash.new { |h, k| h[k] = [] }
@instance_methods = Hash.new { |h, k| h[k] = [] }

puts "=== Teste de Show References com Receiver ==="
puts

# Criar arquivo com definições e chamadas
code = <<~RUBY
  module Trips
    class CacheService
      def self.call(params)
        puts "Called!"
      end
    end
  end

  class SomeController
    def index
      # Chamada com receiver completo
      Trips::CacheService.call(params)
      
      # Chamada com receiver curto (simulado)
      CacheService.call(params)
    end
  end
  
  # Referência textual (include)
  class OtherService
    include Trips::CacheService
  end
RUBY

File.write("tmp_references_test.rb", code)

# Indexar
puts "1. Indexando arquivo..."
index_file("tmp_references_test.rb")

puts "\nReferências indexadas:"
@references.each do |key, refs|
  puts "  #{key}: #{refs.length} referências"
  refs.each do |r|
    puts "    - #{r['method'] ? "Call to .#{r['method']}" : r['type']} em linha #{r['line']}"
  end
end

# Teste 1: Show References em 'call' de 'Trips::CacheService.call'
puts "\n2. Testando Show References para 'Trips::CacheService.call'..."
req_call = {
  "word" => "call",
  "receiver" => "Trips::CacheService",
  "file" => "tmp_references_test.rb"
}

results_call = handle_references(req_call)
puts "Resultados encontrados: #{results_call.length}"
results_call.each do |r|
  puts "  ✓ #{r['preview']} (linha #{r['line']})"
end

# Validação Teste 1
has_call = results_call.any? { |r| r['line'] == 13 } # Linha da chamada Trips::CacheService.call
if has_call
  puts "  ✅ SUCESSO! Encontrou a chamada do método."
else
  puts "  ❌ FALHA! Não encontrou a chamada."
end

# Teste 2: Show References em 'Trips::CacheService' (classe)
puts "\n3. Testando Show References para 'Trips::CacheService' (classe)..."
req_class = {
  "word" => "CacheService",
  "receiver" => "Trips",
  "file" => "tmp_references_test.rb"
}

results_class = handle_references(req_class)
puts "Resultados encontrados: #{results_class.length}"
results_class.each do |r|
  puts "  ✓ #{r['preview']} (linha #{r['line']})"
end

# Validação Teste 2
has_include = results_class.any? { |r| r['preview'].include?("include Trips::CacheService") }
has_call_ref = results_class.any? { |r| r['line'] == 13 } # A chamada também é uma referência à classe
if has_include
  puts "  ✅ SUCESSO! Encontrou referência textual (include)."
else
  puts "  ❌ FALHA! Não encontrou referência textual."
end

if has_call_ref
  puts "  ✅ SUCESSO! Encontrou uso da classe na chamada."
else
  puts "  ❌ FALHA! Não encontrou uso da classe na chamada."
end

# Limpar
File.delete("tmp_references_test.rb") if File.exist?("tmp_references_test.rb")

puts "\n=== Teste concluído! ==="
