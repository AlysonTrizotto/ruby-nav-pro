#!/usr/bin/env ruby
# frozen_string_literal: true

$TESTING = true
require_relative "../server/server"

include RouteIndexer

def assert(cond, msg)
  raise msg unless cond
end

File.write("_routes_ext_test.rb", <<~ROUTES)
  root to: 'home#dashboard'
  options '/cors', to: 'cors#preflight'
  resource :account, only: [:show, :edit], path: 'me'
  namespace :api, path: "v1" do
    resources :posts, only: [:index, :show], path: "articles"
    resources :comments, except: [:destroy]
  end
ROUTES

routes = parse_routes_file("_routes_ext_test.rb")

root_route = routes.find { |r| r.path == "/" && r.action == "dashboard" }
assert root_route && root_route.verb == "GET", "expected root GET / → home#dashboard, got #{root_route.inspect}"

cors = routes.find { |r| r.path == "/cors" && r.action == "preflight" }
assert cors && cors.verb == "OPTIONS", "expected OPTIONS /cors, got #{cors.inspect}"

paths = routes.map(&:path)
assert paths.include?("/me"), "expected singular resource show at /me, got #{paths.inspect}"
assert paths.include?("/me/edit"), "expected singular resource edit at /me/edit"
refute_new = routes.any? { |r| r.path == "/me/new" && r.controller.include?("Account") }
assert !refute_new, "only: [:show, :edit] must not emit /me/new for account"

assert paths.include?("/v1/articles"), "expected /v1/articles for posts path:, got #{paths.inspect}"
assert paths.include?("/v1/articles/:id"), "expected show path under articles"

comment_destroy = routes.find { |r| r.controller.include?("Comments") && r.action == "destroy" }
assert comment_destroy.nil?, "except: [:destroy] should remove destroy, still have #{comment_destroy.inspect}"

comment_index = routes.find { |r| r.path == "/v1/comments" && r.action == "index" }
assert comment_index, "expected index for comments"

File.delete("_routes_ext_test.rb")

puts "OK: route_indexer extended (root, options, singular resource, namespace path, resources path, only/except)"
