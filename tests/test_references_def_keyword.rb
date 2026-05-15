#!/usr/bin/env ruby
# frozen_string_literal: true

# Referências com cursor na linha `def nome` (pedido com word "def" → expande para "nome").

$TESTING = true
require_relative "../server/server"

def assert(cond, msg)
  raise msg unless cond
end

@index = Hash.new { |h, k| h[k] = [] }
@const_map = {}
@relations = Hash.new { |h, k| h[k] = Set.new }
@references = Hash.new { |h, k| h[k] = [] }
@instance_methods = Hash.new { |h, k| h[k] = [] }

code = <<~RUBY
  module Admin
    module Crud
      class Show
        def perform
          @instance = load_object
        end

        private

        def load_object
          true
        end
      end
    end
  end
RUBY

path = File.expand_path("_refs_def_kw.rb", __dir__)
File.write(path, code)
index_file(path)

def_line = 10
r = handle_references("word" => "def", "file" => path, "line" => def_line)
assert r.any? { |x| x["method"] == "load_object" && x["line"] == 5 },
       "expected usage of load_object from expanded def, got #{r.inspect}"

File.delete(path)

puts "OK: references expand def keyword to method name"
