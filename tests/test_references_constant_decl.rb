#!/usr/bin/env ruby
# frozen_string_literal: true

# Ctrl+Shift+D em `class Show` / `module Admin` → referências com receiver = constante.

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

show_path = File.expand_path("_const_show.rb", __dir__)
caller_path = File.expand_path("_const_caller.rb", __dir__)

File.write(show_path, <<~RUBY)
  module Admin
    module Crud
      class Show
        def self.run
          :ok
        end

        def self.demo
          Admin::Crud::Show.run
        end
      end
    end
  end
RUBY

File.write(caller_path, <<~RUBY)
  x = Admin::Crud::Show.run
RUBY

index_file(show_path)
index_file(caller_path)

ln_show = nil
File.foreach(show_path).with_index(1) { |l, i| ln_show = i if l =~ /^\s*class\s+Show\b/ }
raise "class Show line" unless ln_show

hits = handle_references("word" => "Show", "file" => show_path, "line" => ln_show)
assert hits.any? { |h| h["path"] == caller_path && h["preview"].to_s.include?("Admin::Crud::Show") },
       "expected ref in caller, got #{hits.map { |h| [h['path'], h['line'], h['preview']] }}"
assert hits.any? { |h| h["path"] == show_path && h["preview"].to_s.include?("Admin::Crud::Show.run") },
       "expected same-file explicit FQ ref in demo, got #{hits.map { |h| h['preview'] }}"

ln_admin = nil
File.foreach(show_path).with_index(1) { |l, i| ln_admin = i if l =~ /^\s*module\s+Admin\b/ }
hits_ad = handle_references("word" => "Admin", "file" => show_path, "line" => ln_admin)
assert hits_ad.any? { |h| h["path"] == caller_path },
       "expected Admin refs from module decl, got #{hits_ad.inspect}"

File.delete(show_path)
File.delete(caller_path)

puts "OK: references from module/class declaration (Show, Admin)"
