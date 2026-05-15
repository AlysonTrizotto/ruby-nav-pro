def local_var_definition_context?(word, receiver)
  return false if word.nil? || word.empty?
  return false if receiver && !receiver.to_s.empty?
  return false if word.start_with?("@") || word.start_with?("@@")
  return false if word.include?("::") || word.include?("#")
  return false if word =~ /\A[A-Z]/

  true
end

def ripper_normalize_params_node(raw)
  return nil unless raw.is_a?(Array)

  return raw[1] if raw[0] == :paren && raw[1].is_a?(Array) && raw[1][0] == :params
  return raw if raw[0] == :params

  nil
end

def ripper_add_params_to_env(params_node, env)
  return unless params_node.is_a?(Array) && params_node[0] == :params

  (params_node[1] || []).each do |item|
    next unless item.is_a?(Array) && item[0] == :@ident

    env[item[1]] = { "line" => item[2][0], "col" => item[2][1] }
  end

  (params_node[2] || []).each do |pair|
    next unless pair.is_a?(Array) && pair[0].is_a?(Array) && pair[0][0] == :@ident

    id = pair[0]
    env[id[1]] = { "line" => id[2][0], "col" => id[2][1] }
  end

  rest = params_node[3]
  if rest.is_a?(Array) && rest[0] == :rest_param && rest[1].is_a?(Array) && rest[1][0] == :@ident
    id = rest[1]
    env[id[1]] = { "line" => id[2][0], "col" => id[2][1] }
  end

  (params_node[5] || []).each do |kw|
    next unless kw.is_a?(Array) && kw[0].is_a?(Array) && kw[0][0] == :@label

    name = kw[0][1].to_s.sub(/:\z/, "")
    pos = kw[0][2]
    env[name] = { "line" => pos[0], "col" => pos[1] }
  end

  kwrest = params_node[6]
  if kwrest.is_a?(Array) && kwrest[0] == :kwrest_param && kwrest[1].is_a?(Array) && kwrest[1][0] == :@ident
    id = kwrest[1]
    env[id[1]] = { "line" => id[2][0], "col" => id[2][1] }
  end

  blk = params_node[7]
  if blk.is_a?(Array) && blk[0] == :blockarg && blk[1].is_a?(Array) && blk[1][0] == :@ident
    id = blk[1]
    env[id[1]] = { "line" => id[2][0], "col" => id[2][1] }
  end
end

def ripper_record_var_field_assign(lhs, env)
  return unless env && lhs.is_a?(Array) && lhs[0] == :var_field

  id = lhs[1]
  return unless id.is_a?(Array) && id[0] == :@ident

  pos = id[2]
  env[id[1]] = { "line" => pos[0], "col" => pos[1] }
end

def ripper_ident_matches_cursor?(id_node, word, line, col)
  return false unless id_node.is_a?(Array) && id_node[0] == :@ident

  _, nm, pos = id_node
  l, c0 = pos
  l == line && col >= c0 && col < c0 + word.length && nm.to_s == word
end

# ctx: { found: [nil], word:, path:, line:, col: } — found[0] recebe o hit
def ripper_walk_bodystmt_rescues(rescue_node, scopes, ctx)
  cur = rescue_node
  while cur && cur.is_a?(Array) && cur[0] == :rescue
    break if ctx[:found][0]

    exc_var = cur[2]
    exc_body = cur[3]
    ext = cur[4]
    res_env = {}
    if exc_var.is_a?(Array) && exc_var[0] == :var_field && exc_var[1].is_a?(Array) && exc_var[1][0] == :@ident
      id = exc_var[1]
      res_env[id[1]] = { "line" => id[2][0], "col" => id[2][1] }
    end
    rscopes = res_env.empty? ? scopes : (scopes + [res_env])
    (exc_body || []).each do |s|
      ripper_walk_local_binding_sexp(s, rscopes, ctx)
      break if ctx[:found][0]
    end
    cur = ext
  end
end

def ripper_walk_local_binding_sexp(node, scopes, ctx)
  return if ctx[:found][0]
  return unless node.is_a?(Array) && node[0].is_a?(Symbol)

  word = ctx[:word]
  path = ctx[:path]
  line = ctx[:line]
  col = ctx[:col]
  found = ctx[:found]

  case node[0]
  when :var_ref
    id = node[1]
    if ripper_ident_matches_cursor?(id, word, line, col)
      scopes.reverse_each do |env|
        hit = env[word]
        next unless hit

        found[0] = hit.merge("path" => path)
        return
      end
    end
    return
  when :program
    node[1].each { |s| ripper_walk_local_binding_sexp(s, scopes, ctx) }
    return
  when :bodystmt
    node[1].each do |s|
      next if s[0] == :void_stmt

      ripper_walk_local_binding_sexp(s, scopes, ctx)
      return if ctx[:found][0]
    end
    ripper_walk_bodystmt_rescues(node[2], scopes, ctx) if node[2]
    return
  when :def
    env = {}
    pn = ripper_normalize_params_node(node[2])
    ripper_add_params_to_env(pn, env) if pn
    ripper_walk_local_binding_sexp(node[3], scopes + [env], ctx)
    return
  when :defs
    env = {}
    pn = ripper_normalize_params_node(node[4])
    ripper_add_params_to_env(pn, env) if pn
    ripper_walk_local_binding_sexp(node[5], scopes + [env], ctx)
    return
  when :class, :module
    env = {}
    ripper_walk_local_binding_sexp(node[3], scopes + [env], ctx)
    return
  when :sclass
    env = {}
    ripper_walk_local_binding_sexp(node[2], scopes + [env], ctx)
    return
  when :lambda
    env = {}
    pn = ripper_normalize_params_node(node[1])
    ripper_add_params_to_env(pn, env) if pn
    body = node[2]
    if body.is_a?(Array)
      body.each do |s|
        ripper_walk_local_binding_sexp(s, scopes + [env], ctx)
        return if ctx[:found][0]
      end
    end
    return
  when :do_block
    bv, body = node[1], node[2]
    env = {}
    if bv.is_a?(Array) && bv[0] == :block_var
      inner = bv[1]
      pn = ripper_normalize_params_node(inner) || (inner && inner[0] == :params ? inner : nil)
      ripper_add_params_to_env(pn, env) if pn
    end
    ripper_walk_local_binding_sexp(body, scopes + [env], ctx)
    return
  when :brace_block
    bv, body = node[1], node[2]
    env = {}
    if bv.is_a?(Array) && bv[0] == :block_var
      inner = bv[1]
      pn = ripper_normalize_params_node(inner) || (inner && inner[0] == :params ? inner : nil)
      ripper_add_params_to_env(pn, env) if pn
    end
    (body || []).each do |s|
      ripper_walk_local_binding_sexp(s, scopes + [env], ctx)
      return if ctx[:found][0]
    end
    return
  when :assign
    ripper_walk_local_binding_sexp(node[2], scopes, ctx)
    ripper_record_var_field_assign(node[1], scopes.last)
    return
  when :massign
    # a, b = rhs — avaliar rhs antes de ligar nomes
    ripper_walk_local_binding_sexp(node[2], scopes, ctx)
    return if ctx[:found][0]

    (node[1] || []).each do |lhs|
      ripper_record_var_field_assign(lhs, scopes.last)
    end
    return
  when :opassign
    ripper_walk_local_binding_sexp(node[3], scopes, ctx)
    ripper_record_var_field_assign(node[1], scopes.last)
    return
  when :if
    ripper_walk_local_binding_sexp(node[1], scopes, ctx)
    (node[2] || []).each do |s|
      ripper_walk_local_binding_sexp(s, scopes, ctx)
      return if ctx[:found][0]
    end
    if node[3]
      e = node[3]
      if e.is_a?(Array) && e[0] == :else
        (e[1] || []).each do |s|
          ripper_walk_local_binding_sexp(s, scopes, ctx)
          return if ctx[:found][0]
        end
      else
        ripper_walk_local_binding_sexp(e, scopes, ctx)
      end
    end
    return
  when :unless
    ripper_walk_local_binding_sexp(node[1], scopes, ctx)
    (node[2] || []).each do |s|
      ripper_walk_local_binding_sexp(s, scopes, ctx)
      return if ctx[:found][0]
    end
    if node[3]
      e = node[3]
      if e.is_a?(Array) && e[0] == :else
        (e[1] || []).each do |s|
          ripper_walk_local_binding_sexp(s, scopes, ctx)
          return if ctx[:found][0]
        end
      else
        ripper_walk_local_binding_sexp(e, scopes, ctx)
      end
    end
    return
  when :begin
    ripper_walk_local_binding_sexp(node[1], scopes, ctx) if node[1]
    return
  when :while, :until, :for
    node[1..-1].each do |c|
      next unless c.is_a?(Array)

      ripper_walk_local_binding_sexp(c, scopes, ctx)
      return if ctx[:found][0]
    end
    return
  else
    node[1..-1].each do |c|
      next unless c.is_a?(Array)

      ripper_walk_local_binding_sexp(c, scopes, ctx)
      return if ctx[:found][0]
    end
  end
end

def find_local_variable_definition(word, file, line, col)
  return nil if file.to_s.end_with?(".erb")

  path = abs(file)
  return nil unless path && File.file?(path)

  code = File.read(path)
  sexp = Ripper.sexp(code)
  return nil unless sexp.is_a?(Array)

  ctx = { found: [nil], word: word, path: path, line: line, col: col }
  ripper_walk_local_binding_sexp(sexp, [{}], ctx)
  ctx[:found][0]
rescue StandardError => e
  if $VERBOSE || ENV["RUBYNAV_DEBUG"] == "1"
    STDERR.puts "local var definition error #{path || file}: #{e.class}: #{e.message}"
  end
  nil
end
