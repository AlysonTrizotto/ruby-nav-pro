#!/usr/bin/env ruby

# Test script para verificar funcionalidade de hot-reload

# Definir flag para evitar inicialização do servidor
$TESTING = true

require_relative "../server/server"

# Limpar índices anteriores
@index = Hash.new { |h, k| h[k] = [] }
@const_map = {}
@relations = Hash.new { |h, k| h[k] = Set.new }
@references = Hash.new { |h, k| h[k] = [] }
@instance_methods = Hash.new { |h, k| h[k] = [] }

puts "=== Teste de Hot-Reload ==="
puts

# Criar arquivo de teste inicial
test_file = "tmp_test_file.rb"
initial_content = <<~RUBY
  class InitialClass
    def initial_method
      puts "Initial version"
    end
  end
RUBY

File.write(test_file, initial_content)

# Indexar pela primeira vez
puts "1. Indexando arquivo inicial..."
index_file(test_file)

puts "Classes indexadas:"
@index.each do |key, entries|
  entries.each do |e|
    puts "  - #{e['fq']} (#{e['type']}) em #{e['path']}:#{e['line']}"
  end
end

# Simular modificação do arquivo
puts "\n2. Modificando arquivo..."
modified_content = <<~RUBY
  class InitialClass
    def initial_method
      puts "Initial version"
    end
    
    def new_method
      puts "New method added!"
    end
  end
  
  class NewClass
    def another_method
      puts "New class!"
    end
  end
RUBY

File.write(test_file, modified_content)

# Simular comando de re-indexação
puts "3. Re-indexando arquivo modificado..."
req = { "file" => test_file }
handle_reindex_file(req)

puts "\nClasses indexadas após modificação:"
@index.each do |key, entries|
  entries.each do |e|
    if e['path']&.end_with?('tmp_test_file.rb')
      puts "  - #{e['fq']} (#{e['type']}) em #{e['path']}:#{e['line']}"
    end
  end
end

# Simular deleção do arquivo
puts "\n4. Simulando deleção do arquivo..."
File.delete(test_file)
handle_reindex_file(req)

puts "\nClasses indexadas após deleção:"
remaining = @index.values.flatten.select { |e| e['path']&.end_with?('tmp_test_file.rb') }
if remaining.empty?
  puts "  ✓ Arquivo removido do índice com sucesso!"
else
  puts "  ✗ Ainda há entradas no índice:"
  remaining.each do |e|
    puts "    - #{e['fq']}"
  end
end

puts "\n=== Teste concluído! ==="
