# frozen_string_literal: true

# Extrai trechos Ruby de templates ERB (<% ... %>, <%= ... %>, <%- ... -%>, etc.)
# para indexação com Ripper; posições são 1-based line e 0-based col no ficheiro original.

def extract_erb_ruby_fragments(content)
  frags = []
  offset = 0
  len = content.length

  while offset < len
    i = content.index("<%", offset)
    break unless i

    # Literal <%% no ERB
    if content[i, 3] == "<%%"
      offset = i + 3
      next
    end

    body_start = i + 2

    # Comentário ERB <%# ... %>
    if body_start < len && content[body_start] == "#"
      k = content.index("%>", body_start)
      break unless k

      offset = k + 2
      next
    end

    j = body_start
    j += 1 while j < len && content[j] =~ /[=\-]/

    k = content.index("%>", j)
    break unless k

    ruby = content[j...k]
    pre = content[0...j]
    line = pre.count("\n") + 1
    last_nl = pre.rindex("\n")
    col = last_nl ? (j - last_nl - 1) : j

    frags << { text: ruby, line: line, col: col } if ruby.strip.length.positive?

    offset = k + 2
  end

  frags
end
