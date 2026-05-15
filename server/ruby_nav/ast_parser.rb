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
  elsif node[0] == :var_ref
    c = node[1]
    parts << c[1] if c && c[0] == :@const
  elsif node[0] == :@const
    parts << node[1]
  end
end

# Primeira posição Ripper (1-based line, 0-based col) de um :@const no nó do nome (class/module).
def ripper_first_const_decl_pos(const_node)
  return nil unless const_node.is_a?(Array)

  if const_node[0] == :@const
    pos = const_node[2]
    return [pos[0] || 1, pos[1] || 0] if pos
  end

  const_node[1..-1].each do |ch|
    next unless ch.is_a?(Array)

    p = ripper_first_const_decl_pos(ch)
    return p if p
  end

  nil
end

# Chamadas tipo `instance.present?` / `klass.find_by` (receiver não-constante) indexam-se como
# receiver = classe lexical + method = nome antes do ponto, para Show References com inferência de receiver.
BARE_IMPLICIT_NOISE = Set.new(%w[
  puts p print printf sprintf warn raise fail throw catch load require require_relative autoload
  attr_reader attr_writer attr_accessor alias alias_method include extend prepend module_function
  private protected public delegate
  nil true false self defined? block_given? iterator? loop proc lambda binding caller caller_locations
  sleep select rand exec fork exit abort at_exit
  class module def undef return break next redo retry yield super
  trap spawn system
  freeze tap then
  Integer Float String Array Hash Symbol
]).freeze

def constant_like_receiver?(s)
  return false if s.nil?

  tok = s.to_s.split("::").first
  return false if tok.nil? || tok.empty?

  !!(tok =~ /\A[A-Z]/)
end

def record_implicit_self_chain_call!(calls, file, stack, imeth_depth, pos_adj, receiver_node)
  return unless imeth_depth > 0 && stack.any? && receiver_node.is_a?(Array)
  return unless [:vcall, :var_ref].include?(receiver_node[0])

  id = receiver_node[1]
  return unless id && id[0] == :@ident

  base = id[1].to_s
  return if base.empty? || constant_like_receiver?(base) || BARE_IMPLICIT_NOISE.include?(base)

  pos = id[2]
  return unless pos

  line, col = pos_adj.call(pos[0], pos[1])
  calls << {
    "receiver" => stack.join("::"),
    "method"   => base,
    "path"     => abs(file),
    "line"     => line,
    "col"      => col,
    "preview"  => preview_line(file, line)
  }
end

# fragment: String opcional (ex.: trecho ERB). base_line/base_col = posição (1-based / 0-based)
# do primeiro carácter desse fragmento no ficheiro original.
def parse_defs_and_calls(file, source: nil, base_line: 1, base_col: 0)
  code = source.nil? ? File.read(file) : source
  sexp = Ripper.sexp(code)
  return [[], [], {}] unless sexp.is_a?(Array)

  defs = []
  calls = []
  assignments = {}
  stack = []
  imeth_depth = 0

  pos_adj = lambda do |rip_line, rip_col|
    rl = rip_line || 1
    rc = rip_col || 0
    abs_l = base_line + rl - 1
    abs_c = (rl == 1) ? (base_col + rc) : rc
    [abs_l, abs_c]
  end

  walk = lambda do |node|
    return unless node.is_a?(Array)

    case node[0]
    when :module
      name = extract_const(node[1])
      if name
        rp = ripper_first_const_decl_pos(node[1]) || [1, 0]
        al, ac = pos_adj.call(rp[0], rp[1])
        stack << name
        fq = stack.join("::")
        defs << {
          "type" => "module",
          "name" => name.to_s.split("::").last,
          "fq"   => fq,
          "path" => abs(file),
          "line" => al,
          "col"  => ac
        }
        walk.call(node[2]) if node[2].is_a?(Array)
        stack.pop
      end

    when :class
      name = extract_const(node[1])
      if name
        rp = ripper_first_const_decl_pos(node[1]) || [1, 0]
        al, ac = pos_adj.call(rp[0], rp[1])
        stack << name
        fq = stack.join("::")
        defs << {
          "type" => "class",
          "name" => name.to_s.split("::").last,
          "fq"   => fq,
          "path" => abs(file),
          "line" => al,
          "col"  => ac
        }
        walk.call(node[3]) if node[3].is_a?(Array)
        stack.pop
      elsif node[3].is_a?(Array)
        walk.call(node[3])
      end

    when :def
      if node[1] && node[1][0] == :@ident
        mname = node[1][1]
        pos = node[1][2] || [1, 0]
        al, ac = pos_adj.call(pos[0], pos[1])
        fq = (stack + [mname]).join("::")

        if stack.any? && stack.last =~ /Controller$/
          class_name = stack.last
          @instance_methods[class_name] << {
            "name" => mname,
            "path" => abs(file),
            "line" => al,
            "col"  => ac
          }
        end

        if stack.any?
          class_name = stack.last
          @instance_methods[class_name] << {
            "name" => mname,
            "path" => abs(file),
            "line" => al,
            "col"  => ac
          }
        end

        defs << {
          "type" => "method",
          "name" => mname,
          "fq"   => fq,
          "path" => abs(file),
          "line" => al,
          "col"  => ac
        }

        imeth_depth += 1
        begin
          walk.call(node[3]) if node[3].is_a?(Array)
        ensure
          imeth_depth -= 1
        end
      end

    when :defs
      if node[1] && node[3] && node[3][0] == :@ident
        mname = node[3][1]
        pos = node[3][2] || [1, 0]
        al, ac = pos_adj.call(pos[0], pos[1])

        if stack.any?
          class_name = stack.last
          full_class_name = stack.join("::")

          fq_class_method = "#{full_class_name}.#{mname}"

          defs << {
            "type" => "class_method",
            "name" => mname,
            "fq"   => fq_class_method,
            "path" => abs(file),
            "line" => al,
            "col"  => ac
          }

          short_fq = "#{class_name}.#{mname}"
          if short_fq != fq_class_method
            defs << {
              "type" => "class_method",
              "name" => mname,
              "fq"   => short_fq,
              "path" => abs(file),
              "line" => al,
              "col"  => ac
            }
          end

          @instance_methods[full_class_name] << {
            "name" => mname,
            "path" => abs(file),
            "line" => al,
            "col"  => ac,
            "class_method" => true
          }

          @instance_methods[class_name] << {
            "name" => mname,
            "path" => abs(file),
            "line" => al,
            "col"  => ac,
            "class_method" => true
          }
        end

        walk.call(node[5]) if node[5].is_a?(Array)
      end

    when :command_call
      recv = node[1]
      meth = node[3]
      if meth && meth[0] == :@ident
        record_implicit_self_chain_call!(calls, file, stack, imeth_depth, pos_adj, recv)

        recv_name = extract_const_from_receiver(recv)
        if recv_name && constant_like_receiver?(recv_name)
          line, col = pos_adj.call(meth[2][0], meth[2][1])
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
      node[1..-1].each { |c| walk.call(c) if c.is_a?(Array) }

    when :call
      receiver = node[1]
      meth = node[3]
      if meth && meth[0] == :@ident
        record_implicit_self_chain_call!(calls, file, stack, imeth_depth, pos_adj, receiver)

        recv_name = extract_const_from_receiver(receiver)
        if recv_name && constant_like_receiver?(recv_name)
          rl = meth[2] ? meth[2][0] : 1
          rc = meth[2] ? meth[2][1] : 0
          line, col = pos_adj.call(rl, rc)
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
      node[1..-1].each { |c| walk.call(c) if c.is_a?(Array) }

    when :command
      if node[1] && node[1][0] == :@ident
        cmd = node[1][1].to_s
        if %w[attr_reader attr_accessor attr_writer].include?(cmd) && stack.any?
          args = node[2]
          syms = []
          if args.is_a?(Array) && args[0] == :args_add_block && args[1].is_a?(Array)
            args[1].each do |arg|
              next unless arg.is_a?(Array) && arg[0] == :symbol_literal

              sym_node = arg[1]
              next unless sym_node.is_a?(Array) && sym_node[0] == :symbol && sym_node[1].is_a?(Array)
              next unless sym_node[1][0] == :@ident

              sym = sym_node[1][1].to_s
              pos = sym_node[1][2]
              syms << [sym, pos] if sym && !sym.empty? && pos
            end
          end

          class_name = stack.join("::")
          short_cn = stack.last
          syms.each do |sym, pos|
            al, ac = pos_adj.call(pos[0], pos[1])
            fq = "#{class_name}::#{sym}"
            d = {
              "type" => "method",
              "name" => sym,
              "fq"   => fq,
              "path" => abs(file),
              "line" => al,
              "col"  => ac
            }
            defs << d
            @instance_methods[class_name] << {
              "name" => sym,
              "path" => abs(file),
              "line" => al,
              "col"  => ac
            }
            @instance_methods[short_cn] << {
              "name" => sym,
              "path" => abs(file),
              "line" => al,
              "col"  => ac
            } if short_cn && short_cn != class_name
          end
        elsif imeth_depth > 0 && stack.any?
          unless BARE_IMPLICIT_NOISE.include?(cmd)
            pos = node[1][2]
            if pos
              line, col = pos_adj.call(pos[0], pos[1])
              calls << {
                "receiver" => stack.join("::"),
                "method"   => cmd,
                "path"     => abs(file),
                "line"     => line,
                "col"      => col,
                "preview"  => preview_line(file, line)
              }
            end
          end
        end
      end
      node.each { |c| walk.call(c) if c.is_a?(Array) }

    when :assign
      if node[1] && node[1][0] == :var_field && node[2]
        var_name = node[1][1][1] if node[1][1] && node[1][1][0] == :@ident
        if var_name
          assigned_class = extract_const_from_receiver(node[2])
          if assigned_class
            assignments[var_name] = assigned_class
          end
        end
      end
      node[1..-1].each { |c| walk.call(c) if c.is_a?(Array) }

    when :vcall
      if node[1] && node[1][0] == :@ident
        method_name = node[1][1]
        id_pos = node[1][2]
        if assignments[method_name]
          rl = id_pos ? id_pos[0] : 1
          rc = id_pos ? id_pos[1] : 0
          line, col = pos_adj.call(rl, rc)
          calls << {
            "receiver" => assignments[method_name],
            "method"   => method_name,
            "path"     => abs(file),
            "line"     => line,
            "col"      => col,
            "preview"  => preview_line(file, line)
          }
        elsif imeth_depth > 0 && stack.any? && id_pos && !BARE_IMPLICIT_NOISE.include?(method_name.to_s)
          line, col = pos_adj.call(id_pos[0], id_pos[1])
          calls << {
            "receiver" => stack.join("::"),
            "method"   => method_name.to_s,
            "path"     => abs(file),
            "line"     => line,
            "col"      => col,
            "preview"  => preview_line(file, line)
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

def parse_defs_and_calls_erb(file)
  content = File.read(file)
  fragments = extract_erb_ruby_fragments(content)
  all_defs = []
  all_calls = []
  merged_assign = {}

  fragments.each do |frag|
    d, c, a = parse_defs_and_calls(
      file,
      source: frag[:text],
      base_line: frag[:line],
      base_col: frag[:col]
    )
    all_defs.concat(d)
    all_calls.concat(c)
    merged_assign.merge!(a)
  end

  [all_defs, all_calls, merged_assign]
rescue => e
  STDERR.puts "ERB parse error #{file}: #{e.message}"
  [[], [], {}]
end
