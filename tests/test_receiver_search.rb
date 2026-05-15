#!/usr/bin/env ruby

# Teste para validar busca de definições com receiver

$TESTING = true
require_relative "../server/server"

# Limpar índices
@index = Hash.new { |h, k| h[k] = [] }
@const_map = {}
@relations = Hash.new { |h, k| h[k] = Set.new }
@references = Hash.new { |h, k| h[k] = [] }
@instance_methods = Hash.new { |h, k| h[k] = [] }

puts "=== Teste de Busca com Receiver ==="
puts

# Criar arquivos de teste simulando o cenário real
trips_cache_service = <<~RUBY
  module Trips
    class CacheService
      def self.call(params)
        # Implementação do cache
        puts "Trips::CacheService.call"
      end
    end
  end
RUBY

admin_service = <<~RUBY
  module Admin
    class OrderCancellationService
      def self.call(order_id)
        puts "Admin::OrderCancellationService.call"
      end
    end
  end
RUBY

checkout_service = <<~RUBY
  module Checkout
    module Braintree
      class CreditCardChargeService
        def self.call(payment_info)
          puts "Checkout::Braintree::CreditCardChargeService.call"
        end
      end
    end
  end
RUBY

# Escrever arquivos
File.write("tmp_trips_cache_service.rb", trips_cache_service)
File.write("tmp_admin_service.rb", admin_service)
File.write("tmp_checkout_service.rb", checkout_service)

# Indexar
puts "1. Indexando arquivos..."
index_file("tmp_trips_cache_service.rb")
index_file("tmp_admin_service.rb")
index_file("tmp_checkout_service.rb")

puts "\nMétodos de classe indexados:"
@index.each do |key, entries|
  entries.each do |e|
    if e['type'] == 'class_method'
      puts "  - #{e['fq']} em #{File.basename(e['path'])}:#{e['line']}"
    end
  end
end

puts "\nMétodos de instância por classe:"
@instance_methods.each do |class_name, methods|
  puts "  #{class_name}:"
  methods.each do |m|
    prefix = m['class_method'] ? 'self.' : '#'
    puts "    - #{prefix}#{m['name']} em #{File.basename(m['path'])}:#{m['line']}"
  end
end

# Testar busca SEM receiver (problema original)
puts "\n2. Testando busca SEM receiver (antigo comportamento):"
req_without_receiver = {
  "word" => "call",
  "file" => "tmp_trips_cache_service.rb"
}

results_without = handle_definition(req_without_receiver)
puts "Resultados para 'call' (sem receiver): #{results_without.length}"
results_without.first(5).each do |r|
  puts "  - #{r['fq']} em #{File.basename(r['path'])}"
end

# Testar busca COM receiver (novo comportamento)
puts "\n3. Testando busca COM receiver (novo comportamento):"
req_with_receiver = {
  "word" => "call",
  "receiver" => "Trips::CacheService",
  "file" => "tmp_trips_cache_service.rb"
}

results_with = handle_definition(req_with_receiver)
puts "Resultados para 'Trips::CacheService.call': #{results_with.length}"
results_with.each do |r|
  puts "  ✓ #{r['fq']} em #{File.basename(r['path'])}:#{r['line']}"
end

# Validação
puts "\n4. Validação:"
exact_match = results_with.any? { |r| r['fq'] == 'Trips::CacheService.call' }
all_trips_cache = results_with.all? { |r| r['fq'].start_with?('Trips::CacheService') }

if exact_match && all_trips_cache && results_with.length <= 3
  puts "  ✅ SUCESSO! Encontrou apenas Trips::CacheService (#{results_with.length} resultados)"
elsif exact_match
  puts "  ⚠️  Encontrou Trips::CacheService.call, mas com resultados extras"
else
  puts "  ❌ FALHA! Não encontrou Trips::CacheService.call"
end

# Testar outro receiver
puts "\n5. Testando outro receiver: Admin::OrderCancellationService"
req_admin = {
  "word" => "call",
  "receiver" => "Admin::OrderCancellationService",
  "file" => "tmp_admin_service.rb"
}

results_admin = handle_definition(req_admin)
puts "Resultados: #{results_admin.length}"
results_admin.each do |r|
  puts "  ✓ #{r['fq']} em #{File.basename(r['path'])}:#{r['line']}"
end

# Limpar
File.delete("tmp_trips_cache_service.rb") if File.exist?("tmp_trips_cache_service.rb")
File.delete("tmp_admin_service.rb") if File.exist?("tmp_admin_service.rb")
File.delete("tmp_checkout_service.rb") if File.exist?("tmp_checkout_service.rb")

puts "\n=== Teste concluído! ==="
