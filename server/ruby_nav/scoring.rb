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

def receiver_match_score(full_const, receiver)
  full_parts = full_const.to_s.split("::")
  recv_parts = receiver.to_s.split("::")
  score = 0
  i = full_parts.length - 1
  j = recv_parts.length - 1
  while i >= 0 && j >= 0 && full_parts[i] == recv_parts[j]
    score += 1
    i -= 1
    j -= 1
  end
  score
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

# Classe/módulo declarado a partir de fq de método (ex.: "Admin::Crud::Show::perform" -> "Admin::Crud::Show")
def declaring_class_from_entry_fq(fq)
  return nil if fq.nil? || fq.to_s.empty?

  parts = fq.to_s.split("::")
  return nil if parts.length < 2

  parts[0..-2].join("::")
end

# Bónus na ordenação (valores altos = preferir no sort_by { -base }).
def navigation_origin_boost(origin_abs_path, entry_path, entry, inferred_receiver)
  boost = 0
  return boost unless origin_abs_path && entry_path

  o = origin_abs_path.to_s
  e = entry_path.to_s
  boost += 600_000 if o == e
  boost += 450_000 if File.dirname(o) == File.dirname(e)

  if inferred_receiver && !inferred_receiver.to_s.empty? && entry.is_a?(Hash)
    dc = declaring_class_from_entry_fq(entry["fq"])
    boost += 550_000 if dc && dc == inferred_receiver.to_s
  end

  boost
end

def textual_reference_penalty(entry)
  return 0 unless entry.is_a?(Hash)

  entry["type"] == "text" ? -900_000 : 0
end

# Receiver inferido (ex.: Admin::Crud::Show) ainda “é o self” do ficheiro se o tail do namespace coincide
# ou se path_to_const do ficheiro alinha com o receiver (paths app/classes/... vs constante Ruby).
def implicit_receiver_matches_origin_path?(receiver, origin_abs)
  return true if receiver.nil? || receiver.to_s.strip.empty?

  oc = (path_to_const(origin_abs) rescue nil)
  return true if oc.nil? || oc.to_s.empty?

  rx = receiver.to_s
  return true if rx == oc
  return true if rx.split("::").last == oc.split("::").last

  receiver_match_score(oc, rx) >= 1
end

# Classe de `self` para chamadas sem receiver (mesmo critério que handle_references).
def infer_lexical_self_receiver(origin_file, origin_line, word)
  return nil unless origin_file && origin_line && word && !word.to_s.include?("::") && !word.to_s.include?("#")

  of = abs(origin_file)
  ol = origin_line.to_i
  return nil if ol <= 0

  inferred = nil
  if defined?(@index) && @index.is_a?(Hash) && @index[word]
    same_file_defs = @index[word].select do |e|
      e["path"] == of && e["line"] && e["fq"] && e["type"] == "method"
    end
    unless same_file_defs.empty?
      closest = same_file_defs.min_by { |e| (e["line"] - ol).abs }
      if closest && closest["fq"]
        parts = closest["fq"].split("::")
        inferred = parts[0..-2].join("::") if parts.length > 1
      end
    end
  end

  if inferred.nil? || inferred.empty?
    begin
      g = path_to_const(of)
      inferred = g if g && !g.to_s.empty?
    rescue StandardError
    end
  end

  inferred
end

# Referências à constante no **mesmo ficheiro** da declaração: só contam se o texto da linha
# mostra o nome da constante (ex. `Admin::Crud::Show.perform`). Chamadas só implícitas a `self`
# indexam-se com o mesmo receiver mas não escrevem o FQ — não são "usos" da constante.
def reference_explicit_const_in_line?(ref, fq)
  prev = (ref["preview"] || "").to_s
  return true if prev.include?(fq)

  tail = fq.split("::").last
  return false if tail.nil? || tail.empty?
  return false unless tail =~ /\A[A-Z]/

  return true if prev.match?(/::#{Regexp.escape(tail)}(?:\s*[\.\[\(]|\b)/)
  return true if prev.match?(/(?:^|[^\w:])#{Regexp.escape(tail)}\s*\./)
  return true if prev.match?(/(?:^|[^\w:])#{Regexp.escape(tail)}\s*=/)

  false
end
