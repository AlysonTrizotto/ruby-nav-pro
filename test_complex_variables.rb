#!/usr/bin/env ruby

# Test script para verificar rastreamento de variáveis complexas

require_relative 'server/server'

# Limpar índices anteriores
@index = Hash.new { |h, k| h[k] = [] }
@const_map = {}
@relations = Hash.new { |h, k| h[k] = Set.new }
@references = Hash.new { |h, k| h[k] = [] }
@instance_methods = Hash.new { |h, k| h[k] = [] }

# Criar arquivo de teste com o código complexo do usuário
test_content = <<~RUBY
  class SalesApiService
    def self.call(operator_id, context)
      # Simula retorno de uma classe diferente baseado em condição
      if ["rjv2", "distribusion"].include?(operator_id)
        WhitelabelApi
      else
        StandardApi
      end
    end
  end

  class WhitelabelApi
    def initialize(operator_id, channel, context)
      @operator_id = operator_id
      @channel = channel
      @context = context
    end

    def set_white_label_request(is_white_label)
      puts "Setting white label request: #{is_white_label}"
    end
  end

  class StandardApi
    def initialize(operator_id, channel, context)
      @operator_id = operator_id
      @channel = channel
      @context = context
    end
  end

  class ReservationService
    def sales_api(is_white_label = false, channel = '')
      operator_class = SalesApiService.call(id, self)
      return unless operator_class.present?

      operator_class = operator_class.new(id, channel, self) if %w[rjv2 distribusion ggds impetus j3].include?(operator_class.provider)
      operator_class.set_white_label_request(is_white_label) if operator_class.is_a?(WhitelabelApi)
      operator_class
    end
  end
RUBY

# Escrever arquivo de teste
File.write("test_complex.rb", test_content)

# Indexar o arquivo
puts "Indexando arquivo de teste complexo..."
index_file("test_complex.rb")

puts "\n=== Atribuições encontradas ==="
@references.each do |key, refs|
  refs.each do |ref|
    if ref["type"] == "assignment"
      puts "#{ref['variable']} = #{ref['class']} em #{ref['path']}:#{ref['line']}"
    end
  end
end

puts "\n=== Chamadas de métodos em variáveis ==="
@references.each do |key, refs|
  refs.each do |ref|
    if ref["type"] == "variable_method_call"
      puts "#{ref['variable']}.#{ref['method']} em #{ref['path']}:#{ref['line']}"
    end
  end
end

puts "\n=== Testando busca por 'operator_class.set_white_label_request' ==="
# Testar busca por referências
sym = "operator_class.set_white_label_request"
items = @references[sym] || []

puts "Referências diretas encontradas para '#{sym}': #{items.length}"
items.each do |item|
  puts "  - #{item['preview']} em #{item['path']}:#{item['line']}"
end

# Testar busca por atribuições da variável
puts "\nBuscando atribuições para 'operator_class'..."
if @references["operator_class"]
  @references["operator_class"].each do |ref|
    if ref["type"] == "assignment"
      puts "  - Atribuição: #{ref['class']} em #{ref['path']}:#{ref['line']}"
      
      # Procurar métodos na classe
      methods = find_instance_method(ref["class"], "set_white_label_request")
      if methods.any?
        puts "    Métodos encontrados:"
        methods.each do |method|
          puts "      - #{method['name']} em #{method['path']}:#{method['line']}"
        end
      end
    end
  end
end

# Limpar arquivo de teste
File.delete("test_complex.rb") if File.exist?("test_complex.rb")

puts "\nTeste concluído!"