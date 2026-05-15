#!/usr/bin/env ruby
# frozen_string_literal: true

# Evita indexação em background e o loop stdin quando os testes rodam
# `ruby tests/test_*.rb` (PROGRAM_NAME começa com "test_").
$TESTING = true if File.basename($PROGRAM_NAME).start_with?("test_")

require_relative "ruby_nav/loader"
