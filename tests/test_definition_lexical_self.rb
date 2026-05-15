#!/usr/bin/env ruby
# frozen_string_literal: true

# Go to Definition: chamada sem receiver deve resolver no método da classe lexical (self),
# não listar homónimos noutros ficheiros.

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

show_rb = <<~RUBY
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

other_rb = <<~RUBY
  module Admin
    module Crud
      class Create
        def load_object
          false
        end
      end
    end
  end
RUBY

path_show = File.expand_path("_lexical_self_show.rb", __dir__)
path_other = File.expand_path("_lexical_self_create.rb", __dir__)
File.write(path_show, show_rb)
File.write(path_other, other_rb)

index_file(path_show)
index_file(path_other)

req = {
  "word" => "load_object",
  "file" => path_show,
  "line" => 5
}

hits = handle_definition(req)
assert hits.length == 1, "expected single definition, got #{hits.inspect}"
assert hits[0]["fq"].include?("Show"), "expected Show#load_object, got #{hits[0]['fq'].inspect}"
assert hits[0]["line"] == 10, "expected def load_object line 10, got #{hits[0]['line']}"

File.delete(path_show)
File.delete(path_other)

puts "OK: definition lexical self (load_object sem receiver)"
