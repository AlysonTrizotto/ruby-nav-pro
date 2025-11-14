#!/usr/bin/env ruby

# Test script para verificar a funcionalidade de métodos de instância

require_relative 'server/server'

# Limpar índices anteriores
@index = Hash.new { |h, k| h[k] = [] }
@const_map = {}
@relations = Hash.new { |h, k| h[k] = Set.new }
@references = Hash.new { |h, k| h[k] = [] }
@instance_methods = Hash.new { |h, k| h[k] = [] }

# Criar um arquivo de teste com código Ruby
test_content = <<~RUBY
  class SalesApiService
    def self.call(operator_id)
      # Simula retorno de uma classe diferente baseado em condição
      if ["rjv2", "distribusion"].include?(operator_id)
        WhitelabelApi
      else
        StandardApi
      end
    end
  end

  class WhitelabelApi
    def initialize(operator_id, channel)
      @operator_id = operator_id
      @channel = channel
    end

    def set_white_label_request(is_white_label)
      puts "Setting white label request: #{is_white_label}"
    end
  end

  class StandardApi
    def initialize(operator_id, channel)
      @operator_id = operator_id
      @channel = channel
    end
  end

  # Código de teste
  operator_class = SalesApiService.call("rjv2")
  operator_class = operator_class.new("rjv2", "web") 
  operator_class.set_white_label_request(true) if operator_class.is_a?(WhitelabelApi)
RUBY

# Escrever arquivo de teste
File.write("test_file.rb", test_content)

# Indexar o arquivo
puts "Indexando arquivo de teste..."
index_file("test_file.rb")

puts "\n=== Métodos de instância encontrados ==="
@instance_methods.each do |class_name, methods|
  puts "#{class_name}:"
  methods.each do |method|
    puts "  - #{method['name']} (linha #{method['line']})"
  end
end

puts "\n=== Referências encontradas ==="
@references.each do |key, refs|
  puts "#{key}:"
  refs.each do |ref|
    puts "  - #{ref['type'] || 'call'}: #{ref.inspect}"
  end
end

puts "\n=== Testando busca por método de instância ==="
# Testar busca por WhitelabelApi#set_white_label_request
methods = find_instance_method("WhitelabelApi", "set_white_label_request")
puts "Métodos encontrados para WhitelabelApi#set_white_label_request:"
methods.each do |method|
  puts "  - #{method['path']}:#{method['line']}:#{method['col']}"
end

# Testar busca por referências
puts "\n=== Testando busca por referências ==="
if @references["operator_class"]
  puts "Referências para 'operator_class':"
  @references["operator_class"].each do |ref|
    puts "  - #{ref.inspect}"
  end
end

# Limpar arquivo de teste
File.delete("test_file.rb") if File.exist?("test_file.rb")

puts "\nTeste concluído!"