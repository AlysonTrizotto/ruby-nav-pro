# frozen_string_literal: true

# Utilitários de caminho (ROOT é definido em loader.rb antes do require deste arquivo).

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
  rel = rel.sub(/\.html\.erb\z/i, "")
  rel = rel.sub(/\.(?:rb|erb)\z/i, "")
  parts = rel.split("/")
  parts.map { |p| camelize_part(p) }.join("::")
end

def list_ruby_index_files
  (Dir.glob("**/*.rb") + Dir.glob("**/*.erb")).uniq.reject do |f|
    f.start_with?("node_modules/") ||
      f.start_with?("vendor/") ||
      f.include?("/spec/") ||
      f.include?("/test/")
  end
end

# Nome legado usado no código; inclui `.erb`.
def list_rb_files
  list_ruby_index_files
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
