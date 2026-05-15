#!/usr/bin/env ruby
# frozen_string_literal: true

$TESTING = true
require_relative "../server/server"

def assert(cond, msg)
  raise msg unless cond
end

code = <<~RUBY
  module Admin
    module Crud
      class Show
        def perform
          @instance = load_object
          if instance.present?
            true
          end
        end

        def load_object
          klass.find_by({})
        end
      end
    end
  end
RUBY

path = File.expand_path("_implicit_self_sample.rb", __dir__)
File.write(path, code)

@references.clear
index_file(path)

cn = "Admin::Crud::Show"
refs = (@references[cn] || []).select { |r| r["method"] }

load_hits = refs.select { |r| r["method"] == "load_object" }
assert load_hits.any? { |r| r["line"] == 5 }, "expected load_object use on @instance = load_object line, got #{load_hits.inspect}"

inst_hits = refs.select { |r| r["method"] == "instance" }
assert inst_hits.any? { |r| r["line"] == 6 }, "expected instance in if instance.present?, got #{inst_hits.inspect}"

klass_hits = refs.select { |r| r["method"] == "klass" }
assert klass_hits.any? { |r| r["line"] == 12 }, "expected klass in klass.find_by, got #{klass_hits.inspect}"

File.delete(path)

puts "OK: implicit self chain + assign RHS walk (load_object, instance, klass)"
