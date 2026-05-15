def sanitize(list)
  list.reject { |c| c["path"].nil? || !File.exist?(c["path"]) }
end

# Cursor em `def` / `class` / `module` pode enviar a palavra-chave em vez do nome definido.
def expand_ruby_decl_keyword_under_cursor(word, file_path, line_num)
  return word unless word && file_path && line_num

  ln = line_num.to_i
  return word if ln < 1

  path = abs(file_path)
  line_txt = nil
  File.foreach(path).with_index(1) do |l, i|
    if i == ln
      line_txt = l
      break
    end
  end
  return word unless line_txt

  s = line_txt.sub(/\A\s+/, "")
  case word
  when "def"
    m = s.match(/\Adef\s+self\.([a-zA-Z_]\w*[!?=]?)\b/) || s.match(/\Adef\s+([a-zA-Z_]\w*[!?=]?)\b/)
    return m[1] if m
  when "defs"
    m = s.match(/\Adefs\s+[^:]+:\s*([a-zA-Z_]\w*[!?=]?)\b/)
    return m[1] if m
  when "class"
    return word if line_txt.match?(/\A\s*class\s*<<\s*/)
    m = s.match(/\Aclass\s+([A-Z][A-Za-z0-9_:]*)\b/)
    return m[1] if m
  when "module"
    m = s.match(/\Amodule\s+([A-Z][A-Za-z0-9_:]*)\b/)
    return m[1] if m
  end
  word
rescue StandardError
  word
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

# Última atribuição `@nome =` estritamente antes de `cursor_line` (para leitores de ivar / attr_reader).
def find_nearest_ivar_writer_before_line(file_abs, ivar_token, cursor_line)
  return nil unless file_abs && File.file?(file_abs)
  return nil unless cursor_line.is_a?(Integer) && cursor_line > 1
  return nil unless ivar_token.to_s.start_with?("@")

  best = nil
  File.foreach(file_abs).with_index(1) do |line, ln|
    break if ln >= cursor_line

    next unless line =~ /\A\s*#{Regexp.escape(ivar_token)}\s*=/

    idx = line.index(ivar_token)
    col = idx ? idx : 0
    nm = ivar_token.sub(/^@/, "")
    best = {
      "type"    => "method",
      "name"    => nm,
      "fq"      => "#{ivar_token}=",
      "path"    => file_abs,
      "line"    => ln,
      "col"     => col,
      "preview" => line.strip
    }
  end
  best
rescue StandardError
  nil
end

def send_reply(id, result)
  STDOUT.puts({ reply: id, result: result }.to_json)
  STDOUT.flush
end
