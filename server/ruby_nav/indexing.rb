def find_instance_method(class_name, method_name)
  return [] unless @instance_methods[class_name]
  @instance_methods[class_name].select { |m| m["name"] == method_name }
end

def store_def(key, entry)
  @index[key] << entry
end

# ================================================================
# Indexer
# ================================================================
def index_file(file)
  text = File.read(file)
  erb = file.end_with?(".erb")

  if erb
    extract_erb_ruby_fragments(text).each do |frag|
      scan_relations_text(frag[:text]).each do |sym|
        @relations[sym] << abs(file)
      end
    end
  else
    scan_relations_text(text).each do |sym|
      @relations[sym] << abs(file)
    end
  end

  unless erb
    guessed = path_to_const(file)
    if guessed && !guessed.empty?
      @const_map[guessed] ||= []
      @const_map[guessed] << abs(file)
      short = guessed.split("::").last
      @const_by_short[short] << guessed unless @const_by_short[short].include?(guessed)
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
  end

  defs, calls, assignments = erb ? parse_defs_and_calls_erb(file) : parse_defs_and_calls(file)
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
