#!/usr/bin/env ruby
require "json"
require "ripper"
require "pathname"
require "set"

# ================================================================
# Ruby Navigation Pro - SERVER with RouteIndexer (Final)
# ================================================================

ROOT = Dir.pwd

# -------------------------------------------------------------
# Utility: absolute path resolver
# -------------------------------------------------------------
def abs(path)
  return nil unless path
  File.expand_path(path, ROOT)
end

def camelize_part(s)
  s.split("_").map(&:capitalize).join
end

def path_to_const(path)
  rel = Pathname.new(path).cleanpath.to_s
  rel = rel.sub(%r{^/}, "")
  rel = rel.sub(%r{^app/}, "")
  rel = rel.sub(%r{^lib/}, "")
  rel = rel.sub(/\.rb$/, "")
  parts = rel.split("/")
  parts.map { |p| camelize_part(p) }.join("::")
end

def list_rb_files
  Dir.glob("**/*.rb").reject do |f|
    f.start_with?("node_modules/") ||
      f.start_with?("vendor/") ||
      f.include?("/spec/") ||
      f.include?("/test/")
  end
end

def preview_line(file, line)
  l = nil
  File.foreach(file).with_index(1) do |txt, ln|
    if ln == line
      l = txt.strip
      break
    end
  end
  l || ""
rescue
  ""
end

# ================================================================
# Instance method finder
# ================================================================
def find_instance_method(class_name, method_name)
  return [] unless @instance_methods[class_name]
  @instance_methods[class_name].select { |m| m["name"] == method_name }
end

# ================================================================
# RouteIndexer - parse minimal routes DSL to map controller#action
# ================================================================
module RouteIndexer
  Route = Struct.new(:verb, :path, :controller, :action, :file_path)

  module_function

  # Normalize a token like :users or "users" or users
  def normalize_token(tok)
    tok.to_s.gsub(/[:'"]/, "")
  end

  # Simple parsing of config/routes.rb with support for:
  # namespace, scope (path/module), resources (basic), get/post/put/patch/delete => to: 'controller#action'
  def parse_routes_file(path)
    return [] unless File.exist?(path)

    text = File.read(path)
    lines = text.each_line.to_a
    stack = []
    routes = []
    current_file = path

    # helper to current path prefix (from scopes with path or namespaces)
    path_prefix = lambda {
      stack.select { |x| [:path, :ns].include?(x[:type]) }.map { |x| x[:name] }.reject(&:empty?).join("/")
    }

    controller_prefix = lambda {
      stack.select { |x| [:ns, :module].include?(x[:type]) }.map { |x| x[:name].to_s }.map { |c| camelize_controller_prefix(c) }.join("::")
    }

    lines.each_with_index do |raw, ln|
      line = raw.strip
      # skip comments and blank
      next if line.start_with?("#") || line.empty?

      # namespace :api do
      if line =~ /^namespace\s+:?([a-zA-Z0-9_]+)/
        ns = $1.to_s
        stack << { type: :ns, name: ns }
        next
      end

      # scope module: 'admin', path: 'admin'
      if line =~ /^scope\s+(.*)/
        body = $1
        if body =~ /module:\s*['"]([^'"]+)['"]/
          stack << { type: :module, name: $1 }
        end
        if body =~ /path:\s*['"]([^'"]+)['"]/
          stack << { type: :path, name: $1 }
        end
        next
      end

      # resources :users do / resources :users
      if line =~ /^resources\s+:?([a-zA-Z0-9_]+)(\s+do)?/
        res = $1.to_s
        # push resource block or handle simple resources
        if $2
          # Guardar controller atual para uso em rotas member
          ctrl = build_controller_name(controller_prefix.call, res)
          stack << { type: :res, base: res, controller: res, controller_class: ctrl }
        else
          # add basic RESTful patterns (index, show, create, update, destroy) as placeholders
          prefix = [path_prefix.call, res].reject(&:empty?).join("/")
          ctrl = build_controller_name(controller_prefix.call, res)
          routes << Route.new("GET", "/#{prefix}", ctrl, "index", path)
          routes << Route.new("GET", "/#{prefix}/:id", ctrl, "show", path)
          routes << Route.new("POST", "/#{prefix}", ctrl, "create", path)
          routes << Route.new("PUT", "/#{prefix}/:id", ctrl, "update", path)
          routes << Route.new("PATCH", "/#{prefix}/:id", ctrl, "update", path)
          routes << Route.new("DELETE", "/#{prefix}/:id", ctrl, "destroy", path)
        end
        next
      end

      # end of block
      if line == "end"
        stack.pop
        next
      end

      # direct HTTP route: get 'path', to: 'controller#action'
      if line =~ /^(get|post|put|patch|delete)\s+['"]([^'"]+)['"],\s*to:\s*['"]([^'"]+)#([^'"]+)['"]/
        verb = $1.upcase
        path_suffix = $2
        controller_raw = $3
        action = $4

        # controller may be namespaced in string like 'sales/api/v1/reservations'
        ctrl = controller_string_to_controller_class(controller_raw, controller_prefix.call)

        full_path = "/" + [path_prefix.call, path_suffix].reject(&:empty?).join("/")

        routes << Route.new(verb, full_path, ctrl, action, path)
        next
      end

      # post 'trips/operator/:operator_id', to: 'trips#operator'
      if line =~ /^(get|post|put|patch|delete)\s+['"]([^'"]+)['"]\s*,\s*to:\s*['"]([^'"]+)#([^'"]+)['"]/
        verb = $1.upcase
        path_suffix = $2
        controller_raw = $3
        action = $4
        ctrl = controller_string_to_controller_class(controller_raw, controller_prefix.call)
        full_path = "/" + [path_prefix.call, path_suffix].reject(&:empty?).join("/")
        routes << Route.new(verb, full_path, ctrl, action, path)
        next
      end

      # route with controller#action variable style: match 'path', to: 'controller#action', via: :get
      if line =~ /^match\s+['"]([^'"]+)['"]\s*,\s*to:\s*['"]([^'"]+)#([^'"]+)['"]\s*,\s*via:\s*:?(get|post|put|patch|delete)/
        path_suffix = $1
        controller_raw = $2
        action = $3
        verb = $4.upcase
        ctrl = controller_string_to_controller_class(controller_raw, controller_prefix.call)
        full_path = "/" + [path_prefix.call, path_suffix].reject(&:empty?).join("/")
        routes << Route.new(verb, full_path, ctrl, action, path)
        next
      end

      # member routes inside resources blocks like: member do; get :preview; end
      # we'll detect lines like get :preview
      if line =~ /^(get|post|put|patch|delete)\s+:?([a-zA-Z0-9_]+)/
        verb = $1.upcase
        action = $2.to_s
        # try find last :res in stack
        res = stack.reverse.find { |s| s[:type] == :res }
        if res
          base = res[:base]
          # Usar controller armazenado no contexto se disponível
          ctrl = res[:controller_class] || build_controller_name(controller_prefix.call, base)
          full_path = "/" + [path_prefix.call, base, action].reject(&:empty?).join("/")
          routes << Route.new(verb, full_path, ctrl, action, path)
        end
        next
      end

      # custom: direct to 'controller#action' inside resources member: put 'cancel', to: 'reservations#cancel'
      if line =~ /^(get|post|put|patch|delete)\s+['"]([^'"]+)['"]\s*,\s*to:\s*['"]([^'"]+)#([^'"]+)['"]/
        verb = $1.upcase
        path_suffix = $2
        controller_raw = $3
        action = $4
        
        # Se estiver dentro de um bloco resources, usar o controller atual do contexto
        res = stack.reverse.find { |s| s[:type] == :res }
        if res && controller_raw == res[:base]
          # Mesmo controller do resource atual
          ctrl = build_controller_name(controller_prefix.call, controller_raw)
        else
          # Controller diferente, aplicar namespace normalmente
          ctrl = controller_string_to_controller_class(controller_raw, controller_prefix.call)
        end
        
        full_path = "/" + [path_prefix.call, path_suffix].reject(&:empty?).join("/")
        routes << Route.new(verb, full_path, ctrl, action, path)
        next
      end
    end

    routes
  end

  def camelize_controller_prefix(s)
    # e.g. api -> Api ; api/v1 -> Api::V1
    s.to_s.split("/").map { |p| p.split("_").map(&:capitalize).join }.join("::")
  end

  def controller_string_to_controller_class(controller_raw, controller_prefix)
    # controller_raw may be like "trips" or "sales/api/v1/reservations"
    # transform to XxxController with namespace
    token = controller_raw.to_s
    if token.include?("/")
      parts = token.split("/")
      ctrl = parts.map { |p| p.split("_").map(&:capitalize).join }.join("::") + "Controller"
      return ctrl
    else
      # single token: apply prefix if present
      ctrl_name = token.split("_").map(&:capitalize).join + "Controller"
      return controller_prefix && !controller_prefix.empty? ? "#{controller_prefix}::#{ctrl_name}" : ctrl_name
    end
  end

  def build_controller_name(prefix, base)
    ctrl = base.to_s.split("_").map(&:capitalize).join + "Controller"
    return prefix && !prefix.empty? ? "#{prefix}::#{ctrl}" : ctrl
  end
end

# ================================================================
# Global structures for routes
# ================================================================
ROUTES = RouteIndexer.parse_routes_file("config/routes.rb") rescue []
ROUTE_BY_CONTROLLER = Hash.new { |h, k| h[k] = [] }
ROUTE_BY_ACTION = Hash.new { |h, k| h[k] = [] }

ROUTES.each do |r|
  ROUTE_BY_CONTROLLER[r.controller] << r
  key = "#{r.controller}##{r.action}"
  ROUTE_BY_ACTION[key] << r
end

# ================================================================
# AST helpers and indexing (definitions + calls)
# ================================================================
def scan_relations_text(code)
  syms = Set.new
  code.scan(/([A-Z][A-Za-z0-9_:]+)/) { |m| syms << m[0] }
  syms.delete_if { |s| s.length < 2 }
  syms.to_a
end

def extract_const(node)
  return nil unless node.is_a?(Array)

  if node[0] == :const_ref && node[1] && node[1][0] == :@const
    return node[1][1]
  elsif node[0] == :@const
    return node[1]
  elsif node[0] == :const_path_ref
    parts = []
    collect_const_path(node, parts)
    return parts.join("::") unless parts.empty?
  end
  nil
end

def extract_const_from_receiver(node)
  return nil unless node.is_a?(Array)

  case node[0]
  when :var_ref
    c = node[1]
    return c[1] if c && c[0] == :@const

  when :const_ref
    c = node[1]
    return c[1] if c && c[0] == :@const

  when :const_path_ref
    parts = []
    collect_const_path(node, parts)
    return parts.join("::") unless parts.empty?

  when :vcall
    c = node[1]
    return c[1] if c && c[0] == :@const
  end

  nil
end

def collect_const_path(node, parts)
  return unless node.is_a?(Array)

  if node[0] == :const_path_ref
    collect_const_path(node[1], parts)
    r = node[2]
    if r && r[0] == :@const
      parts << r[1]
    elsif r && r[0] == :const_ref
      c = r[1]
      parts << c[1] if c && c[0] == :@const
    end
  elsif node[0] == :const_ref
    c = node[1]
    parts << c[1] if c && c[0] == :@const
  elsif node[0] == :@const
    parts << node[1]
  end
end

def parse_defs_and_calls(file)
  code = File.read(file)
  sexp = Ripper.sexp(code)
  return [[], [], {}] unless sexp.is_a?(Array)

  defs = []
  calls = []
  assignments = {} # Rastrear atribuições de variáveis
  stack = []

  walk = lambda do |node|
    return unless node.is_a?(Array)

    case node[0]
    when :module
      name = extract_const(node[1])
      if name
        stack << name
        walk.call(node[2]) if node[2].is_a?(Array)
        stack.pop
      end

    when :class
      name = extract_const(node[1])
      if name
        stack << name
        walk.call(node[3]) if node[3].is_a?(Array)
        stack.pop
      end

    when :def
      if node[1] && node[1][0] == :@ident
        mname = node[1][1]
        pos = node[1][2] || [1, 0]
        fq = (stack + [mname]).join("::")
        
        # Armazenar como método de instância se estiver dentro de uma classe
        if stack.any? && stack.last =~ /Controller$/
          class_name = stack.last
          @instance_methods[class_name] << {
            "name" => mname,
            "path" => abs(file),
            "line" => pos[0],
            "col"  => pos[1]
          }
        end
        
        defs << {
          "type" => "method",
          "name" => mname,
          "fq"   => fq,
          "path" => abs(file),
          "line" => pos[0],
          "col"  => pos[1]
        }
      end

    when :command_call
      recv = node[1]
      meth = node[3]
      if meth && meth[0] == :@ident
        recv_name = extract_const_from_receiver(recv)
        if recv_name
          line = meth[2][0]
          col  = meth[2][1]
          calls << {
            "receiver" => recv_name,
            "method"   => meth[1],
            "path"     => abs(file),
            "line"     => line,
            "col"      => col,
            "preview"  => preview_line(file, line)
          }
        end
      end

    when :call
      receiver = node[1]
      meth = node[3]
      if meth && meth[0] == :@ident
        recv_name = extract_const_from_receiver(receiver)
        if recv_name
          line = meth[2] ? meth[2][0] : 1
          col  = meth[2] ? meth[2][1] : 0
          calls << {
            "receiver" => recv_name,
            "method"   => meth[1],
            "path"     => abs(file),
            "line"     => line,
            "col"      => col,
            "preview"  => preview_line(file, line)
          }
        end
      end
      
    when :assign
      # Detectar atribuições: variavel = alguma_coisa
      if node[1] && node[1][0] == :var_field && node[2]
        var_name = node[1][1][1] if node[1][1] && node[1][1][0] == :@ident
        if var_name
          # Tentar extrair a classe sendo instanciada
          assigned_class = extract_const_from_receiver(node[2])
          if assigned_class
            assignments[var_name] = assigned_class
          end
        end
      end
      
    when :vcall
      # Chamadas de métodos em variáveis: variavel.metodo
      if node[1] && node[1][0] == :@ident
        method_name = node[1][1]
        # Procurar por atribuições anteriores para inferir a classe
        if assignments[method_name]
          calls << {
            "receiver" => assignments[method_name],
            "method"   => method_name,
            "path"     => abs(file),
            "line"     => node[1][2] ? node[1][2][0] : 1,
            "col"      => node[1][2] ? node[1][2][1] : 0,
            "preview"  => preview_line(file, node[1][2] ? node[1][2][0] : 1)
          }
        end
      end
      
    else
      node.each { |c| walk.call(c) if c.is_a?(Array) }
    end
  end

  walk.call(sexp)
  [defs, calls, assignments]
rescue => e
  STDERR.puts "AST parse error #{file}: #{e.message}"
  [[], [], {}]
end

# ================================================================
# Global indexes
# ================================================================
@index      = Hash.new { |h, k| h[k] = [] }
@const_map  = {}
@relations  = Hash.new { |h, k| h[k] = Set.new }
@references = Hash.new { |h, k| h[k] = [] }
@instance_methods = Hash.new { |h, k| h[k] = [] } # Métodos de instância por classe

def store_def(key, entry)
  @index[key] << entry
end

# ================================================================
# Indexer
# ================================================================
def index_file(file)
  text = File.read(file)
  scan_relations_text(text).each do |sym|
    @relations[sym] << abs(file)
  end

  guessed = path_to_const(file)
  if guessed && !guessed.empty?
    @const_map[guessed] ||= []
    @const_map[guessed] << abs(file)
    store_def(guessed, {
      "type" => "const",
      "name" => guessed.split("::").last,
      "fq"   => guessed,
      "path" => abs(file),
      "line" => 1,
      "col"  => 0
    })
  end

  text.scan(/^\s*(class|module)\s+([A-Z][A-Za-z0-9_:]*)/) do |kind, fq|
    store_def(fq, {
      "type" => kind,
      "name" => fq.split("::").last,
      "fq"   => fq,
      "path" => abs(file),
      "line" => nil,
      "col"  => 0
    })
  end

  defs, calls, assignments = parse_defs_and_calls(file)
  defs.each do |d|
    store_def(d["fq"], d)
    store_def(d["name"], d)
  end

  calls.each do |c|
    recv = c["receiver"]
    next unless recv
    @references[recv] << c
    short = recv.split("::").last
    @references[short] << c
  end
  
  # Armazenar atribuições de variáveis para referência futura
  assignments.each do |var_name, class_name|
    @references[class_name] ||= []
    @references[class_name] << {
      "type" => "assignment",
      "variable" => var_name,
      "class" => class_name,
      "path" => abs(file)
    }
  end
end

def index_workspace
  files = list_rb_files
  total = files.size
  done = 0
  files.each do |f|
    begin
      index_file(f)
    rescue => e
      STDERR.puts "Index error #{f}: #{e.message}"
    end
    done += 1
    STDOUT.puts({ event: "index_progress", done: done, total: total }.to_json)
    STDOUT.flush
  end
  STDOUT.puts({ event: "index_done" }.to_json)
  STDOUT.flush
end

# start indexing in background
Thread.new { index_workspace }

# ================================================================
# Helpers
# ================================================================
def sanitize(list)
  list.reject { |c| c["path"].nil? || !File.exist?(c["path"]) }
end

def find_symbol_occurrences(file, sym)
  results = []
  File.foreach(file).with_index(1) do |line, ln|
    idx = line.index(sym)
    next unless idx

    results << {
      "path"    => abs(file),
      "line"    => ln,
      "col"     => idx,
      "preview" => line.strip,
      "type"    => "text"
    }
  end
  results
rescue
  []
end

def send_reply(id, result)
  STDOUT.puts({ reply: id, result: result }.to_json)
  STDOUT.flush
end

# Adicionar require necessário
require 'etc'

class Server
  CACHE_SIZE = 800
  THREAD_POOL_SIZE = [Etc.nprocessors, 2].max

  def initialize
    @running = true
    @queue = Queue.new
    @pool = Array.new(THREAD_POOL_SIZE) { Thread.new { worker_loop } }
    puts "Servidor nativo iniciado com #{THREAD_POOL_SIZE} threads"
  end

  def worker_loop
    while @running
      task = @queue.pop
      process_task(task)
    end
  end

  def stop
    @running = false
    @pool.each { |t| t.wakeup if t.status == 'sleep' }
    @pool.each(&:join)
    puts "Servidor finalizado com sucesso"
  end
  BATCH_SIZE = 150

  def index_files(files)
    files.each_slice(BATCH_SIZE) do |batch|
      contexts = batch.parallel_map(threads: THREAD_POOL_SIZE) do |file|
        next if @processed_files.include?(file)
        [file, analyze_context(file)]
      end.compact

      @mutex.synchronize do
        contexts.each { |f, ctx| @context_cache[f] = ctx }
        @processed_files.merge(contexts.map(&:first))
        send_progress_update
      end
    end
  end

  def analyze_context(file_path)
    parts = File.dirname(file_path).split('/')
    root_idx = parts.index { |p| ['app','lib'].include?(p) }
    return {} unless root_idx

    {
      root: parts[root_idx],
      module: parts[root_idx + 1],
      hierarchy: parts[root_idx..root_idx+2]
    }.compact
  end
end


def context_score(request_context, result_context)
  # Bloquear completamente módulos diferentes
  return -3000 if request_context[:root] != result_context[:root] # app vs lib
  return -2500 if request_context[:module] != result_context[:module]

  # Exigir correspondência completa da hierarquia do módulo
  return 2000 if request_context[:full_hierarchy] == result_context[:full_hierarchy]

  # Penalizar progressivamente por divergências
  mismatch_level = request_context[:full_hierarchy].zip(result_context[:full_hierarchy]).take_while { |a,b| a == b }.size
  score = mismatch_level * 500

  # Bônus decrescente para submodules
  common_submodules = request_context[:submodules] & result_context[:submodules]
  score += common_submodules.size * 300

  score.positive? ? score : 0
end

def extract_context_from_path(path)
  return nil unless path
  parts = File.dirname(path.to_s).split("/")
  idx = parts.index { |p| ["app", "lib"].include?(p) }
  return nil unless idx

  full = parts[idx..-1]
  {
    root: parts[idx],
    module: parts[idx + 1],
    full_hierarchy: full,
    submodules: full[2..-1] || []
  }
end

# ================================================================
# Command handlers (JSON protocol over STDIN/STDOUT)
# ================================================================

def handle_definition(req)
  word = req["word"] || req["symbol"]
  return [] unless word

  list = []

   # Caso especial: controller#action ou reservations#cancel
  if word.include?("#")
    ctrl_raw, act = word.split("#", 2)

    # Tentar resolver para nome de controller completo
    ctrl_class = if ctrl_raw.include?("::")
      ctrl_raw
    else
      ctrl_raw.split("_").map(&:capitalize).join + "Controller"
    end

    key = "#{ctrl_class}##{act}"
    if ROUTE_BY_ACTION[key]
      ROUTE_BY_ACTION[key].each do |route|
        methods = find_instance_method(route.controller, act)
        methods.each do |m|
          list << {
            "type" => "method",
            "name" => act,
            "fq"   => "#{route.controller}##{act}",
            "path" => m["path"],
            "line" => m["line"],
            "col"  => m["col"],
            "preview" => preview_line(m["path"], m["line"])
          }
        end
      end
    end
  end

  # Primeiro tenta pelo nome exato (método ou constante)
  if @index[word]
    list.concat(@index[word])
  end

  # Se for algo como Foo::Bar, também tenta a parte final
  if word.include?("::")
    short = word.split("::").last
    if @index[short]
      list.concat(@index[short])
    end
  end

  list = sanitize(list.uniq)

  origin_file = req["file"]
  if origin_file
    origin_ctx = extract_context_from_path(origin_file)
    if origin_ctx
      list.sort_by! do |entry|
        ctx = extract_context_from_path(entry["path"])
        ctx ? -context_score(origin_ctx, ctx) : 0
      end
    end
  end

  list
end

def handle_references(req)
  sym = req["symbol"] || req["word"]
  return [] unless sym

  list = []

  if @references[sym]
    list.concat(@references[sym])
  end

  # Para símbolos com namespace ou variação simples, tenta chave reduzida
  if sym.include?("::")
    short = sym.split("::").last
    if @references[short]
      list.concat(@references[short])
    end
  end

  # Caso especial: controller#action vindo de rotas
  if sym.include?("#")
    ctrl_raw, act = sym.split("#", 2)

    ctrl_class = if ctrl_raw.include?("::")
      ctrl_raw
    else
      ctrl_raw.split("_").map(&:capitalize).join + "Controller"
    end

    key = "#{ctrl_class}##{act}"
    if ROUTE_BY_ACTION[key]
      ROUTE_BY_ACTION[key].each do |route|
        list << {
          "path"    => abs(route.file_path),
          "line"    => 1,
          "col"     => 0,
          "preview" => "#{route.verb} #{route.path}",
          "type"    => "route"
        }
      end
    end
  end

  # Fallback: se ainda não há referências estruturadas, usar @relations para
  # localizar arquivos que mencionam a constante (ex.: RoutesBasis)
  if list.empty? && @relations[sym]
    @relations[sym].each do |file|
      list.concat(find_symbol_occurrences(file, sym))
    end
  end

  list = sanitize(list.uniq)

  origin_file = req["file"]
  if origin_file
    origin_ctx = extract_context_from_path(origin_file)
    if origin_ctx
      list.sort_by! do |entry|
        ctx = extract_context_from_path(entry["path"])
        ctx ? -context_score(origin_ctx, ctx) : 0
      end
    end
  end

  list
end

def process_command(cmd)
  id = cmd["id"]
  command = cmd["command"]

  return unless id && command

  result = case command
           when "definition"
             handle_definition(cmd)
           when "references"
             handle_references(cmd)
           else
             nil
           end

  send_reply(id, result)
rescue => e
  STDERR.puts "Command error: #{e.class}: #{e.message}"
  send_reply(id, nil) if id
end

# Main loop: lê uma linha JSON por vez de STDIN
Thread.new do
  while (line = STDIN.gets)
    line = line.strip
    next if line.empty?

    begin
      msg = JSON.parse(line)
    rescue JSON::ParserError
      STDERR.puts "Invalid JSON input: #{line.inspect}"
      next
    end

    next unless msg.is_a?(Hash)
    process_command(msg)
  end
end.join