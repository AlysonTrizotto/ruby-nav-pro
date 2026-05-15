#!/usr/bin/env ruby
# frozen_string_literal: true

$TESTING = true
require_relative "../server/server"

def assert(cond, msg)
  raise msg unless cond
end

code = <<~RUBY
  module X
    class Y
      attr_reader :instance
      def perform
        @instance = load_object
        if instance.present?
        end
      end
    end
  end
RUBY

path = File.expand_path("_attr_ivar.rb", __dir__)
File.write(path, code)

hit = find_nearest_ivar_writer_before_line(path, "@instance", 6)
assert hit && hit["line"] == 5, "expected @instance = on line 5, got #{hit.inspect}"

defs = parse_defs_and_calls(path)[0]
assert defs.any? { |d| d["name"] == "instance" && d["fq"].include?("X::Y") }, "attr_reader should index instance method"

File.delete(path)

puts "OK: attr_reader + @instance writer lookup"
