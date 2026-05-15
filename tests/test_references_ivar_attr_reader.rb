#!/usr/bin/env ruby
# frozen_string_literal: true

# @instance + attr_reader :instance → inclui `instance.present?` e `call(instance)`.

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

path = File.expand_path("_refs_ivar_show.rb", __dir__)
File.write(path, <<~RUBY)
  # frozen_string_literal: true

  module Admin
    module Crud
      class Show
        include ActiveModel::Model
        attr_reader :callbacks, :instance, :find_params, :klass

        def perform
          @instance = load_object

          if instance.present?
            show
          else
            errors.add(:instance, :not_found)
            callbacks[:not_found]&.call(self)
          end
        end

        def show
          if valid?
            callbacks[:success]&.call(instance)
          else
            callbacks[:error]&.call(self)
          end
        end

        private

        def load_object
          klass.find_by(find_params)
        end
      end
    end
  end
RUBY

index_file(path)
ln = nil
File.foreach(path).with_index(1) { |l, i| ln = i if l.include?("@instance = load_object") }
raise "line not found" unless ln

hits = handle_references("word" => "@instance", "file" => path, "line" => ln)
previews = hits.map { |h| h["preview"].to_s }

assert hits.any? { |h| h["line"] == ln && h["preview"].to_s.include?("@instance") },
       "expected @instance assign, got #{hits.inspect}"

assert previews.any? { |p| p.include?("instance.present?") },
       "expected reader instance.present?, got #{previews.inspect}"

assert previews.any? { |p| p.include?(".call(instance)") },
       "expected call(instance), got #{previews.inspect}"

File.delete(path)

puts "OK: @instance refs include attr_reader usages (present?, call(arg))"
