# frozen_string_literal: true

# Carrega o servidor RubyNav em partes (path, rotas, AST, índice, comandos).
# O binário da extensão executa `ruby server/server.rb` com cwd = raiz do workspace.

ROOT = Dir.pwd unless defined?(ROOT)

require "json"
require "pathname"
require "ripper"
require "set"

require_relative "path_utils"
require_relative "route_indexer"
require_relative "routes_setup"
require_relative "globals"
require_relative "erb_support"
require_relative "ast_parser"
require_relative "indexing"
require_relative "local_variables"
require_relative "scoring"
require_relative "protocol"
require_relative "commands"

Thread.new { index_workspace } unless $TESTING

unless $TESTING
  Thread.new do
    while (line = STDIN.gets)
      line = line.strip
      next if line.empty?

      begin
        msg = JSON.parse(line)
      rescue JSON::ParserError
        STDERR.puts "Invalid JSON input: #{line.inspect}"
        next
      end

      next unless msg.is_a?(Hash)
      process_command(msg)
    end
  end.join
end
