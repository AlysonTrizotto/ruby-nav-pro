#!/usr/bin/env ruby

# Test script para verificar a melhoria de contexto em referências de rotas

require_relative 'server/server'

# Limpar índices anteriores
@index = Hash.new { |h, k| h[k] = [] }
@const_map = {}
@relations = Hash.new { |h, k| h[k] = Set.new }
@references = Hash.new { |h, k| h[k] = [] }
@instance_methods = Hash.new { |h, k| h[k] = [] }

# Criar arquivos de teste para simular diferentes contextos
routes_content = <<~RUBY
  Rails.application.routes.draw do
    resources :reservations do
      put 'cancel', to: 'reservations#cancel', as: :cancel
    end
  end
RUBY

controller_content = <<~RUBY
  class ReservationsController < ApplicationController
    def cancel
      # Lógica de cancelamento
    end
  end
RUBY

# Escrever arquivos de teste
File.write("config/routes.rb", routes_content)
File.write("app/controllers/reservations_controller.rb", controller_content)

# Indexar os arquivos
puts "Indexando arquivos de teste..."
index_file("config/routes.rb")
index_file("app/controllers/reservations_controller.rb")

puts "\n=== Rotas encontradas ==="
ROUTES.each do |route|
  puts "#{route.verb} #{route.path} => #{route.controller}##{route.action} (arquivo: #{route.file_path})"
end

puts "\n=== Referências de rotas ==="
if ROUTE_BY_ACTION["ReservationsController#cancel"]
  puts "Rotas para ReservationsController#cancel:"
  ROUTE_BY_ACTION["ReservationsController#cancel"].each do |route|
    puts "  - #{route.verb} #{route.path} em #{route.file_path}"
  end
end

# Testar busca por referências com contexto
puts "\n=== Testando busca por referências com contexto ==="

# Simular uma requisição de referências para "reservations#cancel" vinda de routes.rb
puts "Buscando referências para 'reservations#cancel' com contexto de routes.rb:"

# Filtrar por contexto (simulando a lógica do handler)
sym = "reservations#cancel"
current_file = File.expand_path("config/routes.rb")
ctrl_raw, act = sym.split("#", 2)
ctrl = ctrl_raw.split("_").map(&:capitalize).join + "Controller"

list = []
if ROUTE_BY_ACTION["#{ctrl}##{act}"]
  routes = ROUTE_BY_ACTION["#{ctrl}##{act}"]
  
  puts "Encontradas #{routes.length} rotas:"
  routes.each do |r|
    puts "  - #{r.verb} #{r.path} em #{r.file_path}"
  end
  
  # Se houver múltiplas rotas, filtrar por contexto
  if current_file && routes.length > 1
    puts "Filtrando por contexto (arquivo atual: #{current_file})..."
    same_file_routes = routes.select { |r| abs(r.file_path) == current_file }
    puts "Rotas do mesmo arquivo: #{same_file_routes.length}"
    routes = same_file_routes unless same_file_routes.empty?
  end
  
  routes.each do |r|
    list << {
      "path"    => abs(r.file_path),
      "line"    => 1,
      "col"     => 0,
      "preview" => "#{r.verb} #{r.path}"
    }
  end
end

puts "\nResultados finais:"
list.each do |result|
  puts "  - #{result['preview']} em #{result['path']}"
end

# Limpar arquivos de teste
File.delete("config/routes.rb") if File.exist?("config/routes.rb")
File.delete("app/controllers/reservations_controller.rb") if File.exist?("app/controllers/reservations_controller.rb")

puts "\nTeste concluído!"