#!/usr/bin/env ruby
# frozen_string_literal: true

# Referências a `@ivar` com o cursor na própria variável (ex.: declaração).

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
  module M
    class C
      attr_reader :instance

      def perform
        @instance = load_object
        @instance.to_s
        if instance.nil?
          1
        end
      end

      def load_object
        @instance
      end
    end
  end
RUBY

path = File.expand_path("_refs_ivar_decl.rb", __dir__)
File.write(path, code)
index_file(path)

# Linha da declaração: @instance = load_object
req = { "word" => "@instance", "file" => path, "line" => 6 }
hits = handle_references(req)
lines = hits.map { |h| h["line"] }.uniq.sort
assert lines.include?(6), "expected decl line 6, got #{hits.inspect}"
assert lines.include?(7), "expected @instance line 7, got #{hits.inspect}"
assert lines.include?(8), "expected if instance.nil? line 8, got #{hits.inspect}"
assert lines.include?(14), "expected use in load_object line 14, got #{hits.inspect}"

File.delete(path)

puts "OK: references for @instance from declaration line"
