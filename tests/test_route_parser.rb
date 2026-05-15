#!/usr/bin/env ruby

# Script de teste para verificar o parsing de rotas e mapeamento de controllers

require_relative "../server/server"

# Carregar o RouteIndexer
include RouteIndexer

# Testar o parsing da rota específica
routes_content = <<-ROUTES
  scope module: 'sales' do
    namespace :api do
      namespace :v2 do
        namespace :whats_app do
          resources :reservations do
            put 'cancel', to: 'reservations#cancel', as: :cancel
          end
        end
      end
    end
  end
ROUTES

# Criar arquivo de teste temporário
File.write("test_routes.rb", routes_content)

# Parsear as rotas
routes = RouteIndexer.parse_routes_file("test_routes.rb")

puts "=== Rotas parseadas ==="
routes.each do |r|
  puts "#{r.verb} #{r.path} → #{r.controller}##{r.action}"
end

puts "\n=== Mapeamento por controller#action ==="
ROUTE_BY_ACTION.each do |key, value|
  puts "#{key}:"
  value.each { |r| puts "  #{r.verb} #{r.path}" }
end

puts "\n=== Teste de priorização ==="
# Simular a lógica de priorização
current_file = "/home/alyson/Documentos/ruby-nav-pro/Exemplos/file_1.txt"
ctrl_raw = "reservations"
act = "cancel"

route_controllers = ROUTES
  .select { |r| r.action == act && r.controller.downcase.include?(ctrl_raw.downcase) }
  .map(&:controller)
  .uniq

puts "Controllers encontrados para #{ctrl_raw}##{act}:"
route_controllers.each do |c|
  score = 0
  parts = c.split("::")
  parts.each do |part|
    if current_file.downcase.include?(part.downcase)
      score += 10
    end
  end
  puts "  #{c} (score: #{score}, profundidade: #{parts.length})"
end

# Limpar
File.delete("test_routes.rb") if File.exist?("test_routes.rb")