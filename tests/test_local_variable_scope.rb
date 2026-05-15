#!/usr/bin/env ruby
# frozen_string_literal: true

$TESTING = true
require_relative "../server/server"

def assert(cond, msg)
  raise msg unless cond
end

path = File.expand_path("_demo_body.rb", __dir__)
hit = find_local_variable_definition("result", path, 8, 4)
assert hit, "expected local binding for `result` on use line (col 4 per Ripper)"
assert hit["line"] == 7, "expected definition on assign line 7, got #{hit.inspect}"

puts "OK: local variable not shadowed by same-file method name"
