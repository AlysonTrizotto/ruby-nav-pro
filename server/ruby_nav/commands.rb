def handle_definition(req)
  word = req["word"] || req["symbol"]
  return [] unless word

  receiver = req["receiver"] # Ex: "Trips::CacheService"
  list = []

  origin_file = req["file"]
  origin_line = req["line"]
  req_col = (req["col"] || 0).to_i

  if origin_file && origin_line
    word = expand_ruby_decl_keyword_under_cursor(word, origin_file, origin_line)
  end

  lexical_self_class = infer_lexical_self_receiver(origin_file, origin_line, word) if origin_file && origin_line

  if ENV["RUBYNAV_DEBUG"] == "1"
    STDERR.puts "[rubynav] definition word=#{word.inspect} receiver=#{receiver.inspect} file=#{origin_file.inspect} line=#{origin_line.inspect} col=#{req_col}"
  end

  if local_var_definition_context?(word, receiver) && origin_file && origin_line
    hit = find_local_variable_definition(word, origin_file, origin_line.to_i, req_col)
    if hit
      return [{
        "type" => "local",
        "name" => word,
        "fq" => word,
        "path" => hit["path"],
        "line" => hit["line"],
        "col" => hit["col"]
      }]
    end
  end

  # attr_reader :instance → uso de `instance` deve poder ir para `@instance = …` no mesmo ficheiro
  if origin_file && origin_line && word =~ /\A[a-z_][a-zA-Z0-9_]*\z/ && !word.start_with?("@") && !word.include?("#") && !word.include?("::")
    ap = abs(origin_file)
    if implicit_receiver_matches_origin_path?(receiver, ap)
      hit_iv = find_nearest_ivar_writer_before_line(ap, "@#{word}", origin_line.to_i)
      return [hit_iv] if hit_iv
    end
  end

  # Heurística para variáveis de instância: @origin -> def set_origin
  if word.start_with?("@")
    ivar = word.sub(/^@/, "")

    if origin_file && !ivar.empty?
      setter_name = "set_#{ivar}"
      if @index[setter_name]
        candidates = @index[setter_name].select do |e|
          e["path"] == abs(origin_file) && e["line"]
        end

        unless candidates.empty?
          closest = if origin_line
            candidates.min_by { |e| (e["line"] - origin_line).abs }
          else
            candidates.first
          end

          return [closest].compact if closest
        end
      end
    end
  end

  # Priorizar método no mesmo arquivo — mas NÃO para tokens com forma de
  # variável local (minúscula etc.): senão `result = 1` perde para `def result`.
  if origin_file && origin_line && @index[word] && !local_var_definition_context?(word, receiver)
    same_file_defs = @index[word].select { |e| e["path"] == abs(origin_file) && e["line"] }
    unless same_file_defs.empty?
      closest = same_file_defs.min_by { |e| (e["line"] - origin_line).abs }
      return [closest].compact
    end
  end

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

  # Se temos receiver explícito ou classe lexical inferida (self), buscar método nessa classe
  rx = (receiver && !receiver.to_s.strip.empty?) ? receiver : lexical_self_class
  if rx && !rx.to_s.strip.empty?
    exact_matches = []
    partial_matches = []

    parts = rx.split("::")
    short_name = parts.last
    possible_receivers = []

    # 1) Melhor candidato de nome completo com base em @const_by_short
    if @const_by_short[short_name] && !@const_by_short[short_name].empty?
      origin_abs_path = origin_file ? abs(origin_file) : nil
      origins_dir = origin_abs_path ? File.dirname(origin_abs_path) : nil
      homes = @const_by_short[short_name]

      best_full = homes.max_by do |full|
        sc = receiver_match_score(full, rx)
        if origins_dir && (@const_map[full] || []).any? { |p| File.dirname(p.to_s) == origins_dir }
          sc += 50_000
        end
        sc
      end
      possible_receivers << best_full if best_full
    end

    # 2) Receiver como escrito e nome curto
    possible_receivers << rx
    possible_receivers << short_name
    possible_receivers.uniq!

    possible_receivers.each_with_index do |recv, idx|
      is_exact = (idx == 0) # primeira variação é a mais específica
      
      # Buscar método de instância
      methods = find_instance_method(recv, word)
      methods.each do |m|
        result = {
          "type" => "method",
          "name" => word,
          "fq"   => "#{recv}##{word}",
          "path" => m["path"],
          "line" => m["line"],
          "col"  => m["col"],
          "preview" => preview_line(m["path"], m["line"])
        }
        
        if is_exact
          exact_matches << result
        else
          partial_matches << result
        end
      end

      # Buscar método de classe (self.method)
      fq_method = "#{recv}.#{word}"
      if @index[fq_method]
        @index[fq_method].each do |entry|
          if is_exact
            exact_matches << entry
          else
            partial_matches << entry
          end
        end
      end
    end

    all_matches = exact_matches + partial_matches
    unless all_matches.empty?
      list = sanitize(all_matches.uniq)

      if rx
        begin
          scores = list.map do |entry|
            if entry["path"]
              receiver_match_score(path_to_const(entry["path"]), rx)
            else
              0
            end
          end
          best_recv_score = scores.max || 0

          if best_recv_score > 0
            list = list.select do |entry|
              entry["path"] &&
                receiver_match_score(path_to_const(entry["path"]), rx) == best_recv_score
            end
          end
        rescue
        end
      end

      origin_file = req["file"]
      origin_abs = origin_file ? abs(origin_file) : nil
      if origin_file
        origin_ctx = extract_context_from_path(origin_file)
        if origin_ctx
          list.sort_by! do |entry|
            ctx = extract_context_from_path(entry["path"])
            base = ctx ? context_score(origin_ctx, ctx) : 0

            # Boost adicional: quanto bem o arquivo combina com o receiver pelo caminho
            if rx && entry["path"]
              begin
                guessed_const = path_to_const(entry["path"])
                base += receiver_match_score(guessed_const, rx) * 1500
              rescue
              end
            end

            base += navigation_origin_boost(origin_abs, entry["path"], entry, rx)

            base += 10_000 if exact_matches.include?(entry)
            -base
          end
        end
      end

      return list
    end
  end

  # Primeiro tenta pelo nome exato (método ou constante)
  if @index[word]
    entries = @index[word].dup
    # Sem `Foo.` explícito: não misturar homónimos de outras classes (não fazem parte da cadeia de self).
    if (receiver.nil? || receiver.to_s.strip.empty?) && lexical_self_class && !lexical_self_class.to_s.strip.empty?
      filt = entries.select do |e|
        e["type"] == "method" && declaring_class_from_entry_fq(e["fq"]) == lexical_self_class
      end
      if filt.empty?
        of = abs(origin_file)
        filt = entries.select do |e|
          e["path"] == of && e["type"] == "method" && e["name"].to_s == word.to_s
        end
      end
      entries = filt unless filt.empty?
    end
    list.concat(entries)
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
    origin_abs = abs(origin_file)
    inferred_rx = (receiver && !receiver.to_s.strip.empty?) ? receiver : lexical_self_class
    origin_ctx = extract_context_from_path(origin_file)
    list.sort_by! do |entry|
      ctx = extract_context_from_path(entry["path"])
      base = (origin_ctx && ctx) ? context_score(origin_ctx, ctx) : 0
      base += navigation_origin_boost(origin_abs, entry["path"], entry, inferred_rx)
      -base
    end
  end

  list
end

def handle_references(req)
  word = req["word"] || req["symbol"]
  return [] unless word
  receiver = req["receiver"]
  
  list = []

  # Caso especial: controller#action vindo de rotas
  if word.include?("#")
    ctrl_raw, act = word.split("#", 2)
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
    return sanitize(list.uniq)
  end

  origin_file = req["file"] ? abs(req["file"]) : nil
  origin_file_for_ctx = req["file"]
  origin_line = req["line"]

  if origin_file_for_ctx && origin_line
    word = expand_ruby_decl_keyword_under_cursor(word, origin_file_for_ctx, origin_line)
  end

  def_class = nil

  # Variável de instância: o pedido vem com word "@nome" (ex.: na declaração @instance = …).
  # O bloco mais abaixo só acrescenta "@#{word}" quando word é `instance` sem @.
  if origin_file_for_ctx && word =~ /\A@[a-zA-Z_]\w*\z/
    list.concat(
      find_symbol_occurrences(origin_file_for_ctx, word).each { |r| r["type"] = "ivar" }
    )
    # attr_reader :instance → chamadas a `instance` (self) indexam-se como método "instance"
    reader = word.sub(/\A@/, "")
    if !reader.empty? && origin_line
      ivar_class = infer_lexical_self_receiver(origin_file_for_ctx, origin_line.to_i, reader)
      if ivar_class && !ivar_class.to_s.empty?
        parts = ivar_class.split("::")
        cands = if parts.length >= 2
          (0..parts.length - 2).map { |i| parts[i..-1].join("::") }
        else
          [ivar_class]
        end
        cands.uniq.each do |recv|
          next unless @references[recv]

          @references[recv].each do |ref|
            list << ref if ref["method"] == reader
          end
        end
      end
    end
  end

  const_decl_closest = nil

  # Se não há receiver explícito (ex: estamos em "def call"), tentar inferir
  # a classe/módulo da definição do método no mesmo arquivo ou do path
  if (!receiver || receiver.empty?) && origin_file
    if origin_line && @index[word]
      same_file_defs = @index[word].select do |e|
        e["path"] == origin_file && e["line"] && e["fq"] &&
          %w[method class module].include?(e["type"])
      end

      unless same_file_defs.empty?
        closest = same_file_defs.min_by { |e| (e["line"] - origin_line).abs }
        const_decl_closest = closest if closest && %w[class module].include?(closest["type"])
        if closest && closest["fq"]
          case closest["type"]
          when "class", "module"
            def_class = closest["fq"]
            receiver = closest["fq"]
          when "method"
            parts = closest["fq"].split("::")
            if parts.length > 1
              def_class = parts[0..-2].join("::")
              receiver = def_class
            end
          end
        end
      end
    end

    if (!receiver || receiver.empty?)
      begin
        guessed = path_to_const(origin_file)
        if guessed && !guessed.empty?
          def_class ||= guessed
          receiver = guessed
        end
      rescue
      end
    end
  end

  # 1. Busca por chamadas de método (se houver receiver)
  if receiver && !receiver.empty?
    candidates = []
    parts = receiver.split("::")

    if parts.length >= 2
      # Gerar aliases mantendo sempre pelo menos módulo+classe
      # Ex: ["Sales::Trips::CacheService", "Trips::CacheService"]
      (0..parts.length - 2).each do |i|
        candidates << parts[i..-1].join("::")
      end
    else
      candidates << receiver
    end

    candidates.uniq.each do |recv|
      next unless @references[recv]

      calls = @references[recv].select { |ref| ref["method"] == word }

      if def_class
        def_parts = def_class.split("::")
        min_required = [def_parts.length - 1, 1].max

        calls = calls.select do |ref|
          ref_recv = ref["receiver"]
          next false unless ref_recv
          score = receiver_match_score(def_class, ref_recv)
          score >= min_required
        end
      end

      list.concat(calls)
    end
  end

  # Declaração module/class: chamadas com receiver = constante ou aninhadas.
  # No ficheiro da declaração excluímos chamadas só implícitas a self (sem o FQ/nome qualificado na linha).
  if const_decl_closest && const_decl_closest["fq"]
    fq = const_decl_closest["fq"].to_s
    origin_abs_decl = origin_file_for_ctx ? abs(origin_file_for_ctx) : nil
    @references.each do |recv_key, refs|
      next unless recv_key.is_a?(String)
      next unless recv_key == fq || recv_key.start_with?("#{fq}::")

      refs.each do |ref|
        rp = ref["path"] ? abs(ref["path"]) : nil
        if origin_abs_decl && rp == origin_abs_decl && !reference_explicit_const_in_line?(ref, fq)
          next
        end

        list << ref
      end
    end
  end

  # Fallback: se não achamos nada com receivers específicos mas conhecemos a classe
  # do método, tentar pelas referências do nome curto (ex: "CacheService") e
  # manter apenas as que tiverem melhor compatibilidade de namespace.
  if list.empty? && def_class
    short_name = def_class.split("::").last
    if short_name && @references[short_name]
      short_calls = @references[short_name].select { |ref| ref["method"] == word }

      unless short_calls.empty?
        best_score = short_calls.map { |ref|
          ref_recv = ref["receiver"]
          receiver_match_score(def_class, ref_recv.to_s)
        }.max || 0

        if best_score > 0
          short_calls.select! do |ref|
            ref_recv = ref["receiver"]
            receiver_match_score(def_class, ref_recv.to_s) == best_score
          end
        end

        list.concat(short_calls)
      end
    end
  end

  # 2. Busca por referências à constante (Classe/Módulo)
  # Se o usuário clicou em 'CacheService' de 'Trips::CacheService'
  full_symbol = receiver ? "#{receiver}::#{word}" : word
  
  # Referências onde a constante é usada como receiver (ex: CacheService.new)
  if @references[full_symbol]
    list.concat(@references[full_symbol])
  end
  
  # Se word contém :: (ex: Trips::CacheService sem receiver separado), tratar também
  if word.include?("::") && @references[word]
    list.concat(@references[word])
  end

  # 3. Fallback: Busca textual
  # Se encontramos referências estruturadas, evitamos busca textual ampla
  # Mas se não encontramos nada, ou se é uma busca por classe, tentamos text search
  
  search_terms = []
  
  if list.empty?
    # Se não achou nada estruturado, tenta busca textual
    search_terms << full_symbol
    # Só busca word solta se não tiver receiver (evitar ruído para métodos comuns)
    search_terms << word if word != full_symbol && !receiver 
  else
    # Se achou estruturado, busca textual apenas pelo símbolo completo (para achar includes, etc)
    search_terms << full_symbol
  end
  
  search_terms.uniq.each do |term|
    next if term.length < 3
    if @relations[term]
      @relations[term].each do |file|
        list.concat(find_symbol_occurrences(file, term))
      end
    end
  end

  # Ocorrências de @ivar (ex.: @instance = load_object) no ficheiro onde se pediram referências a `instance`
  if origin_file_for_ctx && word =~ /\A[a-z_][a-zA-Z0-9_]*\z/ && !word.start_with?("@")
    list.concat(find_symbol_occurrences(origin_file_for_ctx, "@#{word}").each { |r| r["type"] = "ivar" })
  end

  list = sanitize(list.uniq)

  if origin_file_for_ctx
    origin_abs_ctx = abs(origin_file_for_ctx)
    inferred = (def_class && !def_class.to_s.empty?) ? def_class : receiver
    origin_ctx = extract_context_from_path(origin_file_for_ctx)
    list.sort_by! do |entry|
      ctx = extract_context_from_path(entry["path"])
      base = (origin_ctx && ctx) ? context_score(origin_ctx, ctx) : 0
      ep = entry["path"] ? abs(entry["path"]) : nil
      base += navigation_origin_boost(origin_abs_ctx, ep, entry, inferred)
      base += textual_reference_penalty(entry)
      -base
    end
  end

  list
end

def rebuild_const_by_short!
  @const_by_short.clear
  @const_map.each do |full, paths|
    next if paths.nil? || paths.empty?

    short = full.to_s.split("::").last
    @const_by_short[short] << full unless @const_by_short[short].include?(full)
  end
end

def handle_reindex_file(req)
  file_path = req["file"]
  return unless file_path

  abs_path = abs(file_path)
  
  # Se o arquivo não existe, removê-lo dos índices
  if !File.exist?(abs_path)
    remove_file_from_index(abs_path)
    return
  end

  # Remover entradas antigas deste arquivo
  remove_file_from_index(abs_path)
  
  # Re-indexar o arquivo
  begin
    index_file(file_path)
    STDERR.puts "Re-indexed: #{file_path}"
  rescue => e
    STDERR.puts "Error re-indexing #{file_path}: #{e.message}"
  end
end

def remove_file_from_index(abs_path)
  # Remover definições
  @index.each do |key, entries|
    @index[key] = entries.reject { |e| e["path"] == abs_path }
  end
  @index.delete_if { |k, v| v.empty? }

  # Remover referências
  @references.each do |key, refs|
    @references[key] = refs.reject { |r| r["path"] == abs_path }
  end
  @references.delete_if { |k, v| v.empty? }

  # Remover métodos de instância
  @instance_methods.each do |class_name, methods|
    @instance_methods[class_name] = methods.reject { |m| m["path"] == abs_path }
  end
  @instance_methods.delete_if { |k, v| v.empty? }

  # Remover do const_map
  @const_map.each do |const, files|
    @const_map[const] = files.reject { |f| f == abs_path }
  end
  @const_map.delete_if { |k, v| v.empty? }

  # Remover relações
  @relations.each do |sym, files|
    files.delete(abs_path)
  end
  @relations.delete_if { |k, v| v.empty? }

  rebuild_const_by_short!
end

def handle_reindex_workspace
  # Limpar todos os índices
  @index.clear
  @const_map.clear
  @relations.clear
  @references.clear
  @instance_methods.clear
   @const_by_short.clear

  # Re-indexar em background
  Thread.new { index_workspace }
end

def process_command(cmd)
  id = cmd["id"]
  command = cmd["command"]

  return unless id && command

  result = case command
           when "definition"
             handle_definition(cmd).tap do |r|
               STDERR.puts "[rubynav] definition hits=#{Array(r).size}" if ENV["RUBYNAV_DEBUG"] == "1"
             end
           when "references"
             handle_references(cmd)
           when "reindex_file"
             handle_reindex_file(cmd)
             { status: "ok", message: "File re-indexed" }
           when "reindex_workspace"
             handle_reindex_workspace
             { status: "ok", message: "Workspace re-indexing started" }
           else
             nil
           end

  send_reply(id, result)
rescue => e
  STDERR.puts "Command error: #{e.class}: #{e.message}"
  send_reply(id, nil) if id
end