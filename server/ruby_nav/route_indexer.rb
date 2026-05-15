module RouteIndexer
  Route = Struct.new(:verb, :path, :controller, :action, :file_path)

  module_function

  # Normalize a token like :users or "users" or users
  def normalize_token(tok)
    tok.to_s.gsub(/[:'"]/, "")
  end

  # Simple parsing of config/routes.rb with support for:
  # root; namespace (com path opcional); scope (path/module);
  # resource (singular) e resources (REST, path:, only:, except:);
  # get/post/.../options + to:, match + via:, member/collection symbol routes
  def parse_routes_file(path)
    return [] unless File.exist?(path)

    text = File.read(path)
    lines = text.each_line.to_a
    stack = []
    routes = []

    # helper to current path prefix (from scopes with path or namespaces)
    path_prefix = lambda {
      stack.select { |x| [:path, :ns].include?(x[:type]) }.map do |x|
        if x[:type] == :path
          x[:name]
        elsif x[:type] == :ns
          (x[:path] && !x[:path].to_s.empty?) ? x[:path] : x[:name]
        end
      end.reject(&:empty?).join("/")
    }

    controller_prefix = lambda {
      stack.select { |x| [:ns, :module].include?(x[:type]) }.map { |x| x[:name].to_s }.map { |c| camelize_controller_prefix(c) }.join("::")
    }

    # Evita "//cors" quando o sufixo começa com "/" (ex.: get '/cors', to: ...)
    route_full_path = lambda do |path_suffix|
      suf = path_suffix.to_s.sub(%r{\A/+}, "")
      parts = [path_prefix.call, suf].reject(&:empty?)
      return "/" if parts.empty?

      "/" + parts.join("/")
    end

    rest_actions_default = %w[index show create update destroy]

    emit_rest_routes = lambda do |path_seg, res_name, ctrl|
      prefix = [path_prefix.call, path_seg].reject(&:empty?).join("/")
      routes << Route.new("GET", "/#{prefix}", ctrl, "index", path)
      routes << Route.new("GET", "/#{prefix}/:id", ctrl, "show", path)
      routes << Route.new("POST", "/#{prefix}", ctrl, "create", path)
      routes << Route.new("PUT", "/#{prefix}/:id", ctrl, "update", path)
      routes << Route.new("PATCH", "/#{prefix}/:id", ctrl, "update", path)
      routes << Route.new("DELETE", "/#{prefix}/:id", ctrl, "destroy", path)
    end

    emit_rest_routes_filtered = lambda do |path_seg, res_name, ctrl, actions|
      prefix = [path_prefix.call, path_seg].reject(&:empty?).join("/")
      actions.each do |act|
        case act
        when "index"
          routes << Route.new("GET", "/#{prefix}", ctrl, "index", path)
        when "show"
          routes << Route.new("GET", "/#{prefix}/:id", ctrl, "show", path)
        when "new"
          routes << Route.new("GET", "/#{prefix}/new", ctrl, "new", path)
        when "edit"
          routes << Route.new("GET", "/#{prefix}/:id/edit", ctrl, "edit", path)
        when "create"
          routes << Route.new("POST", "/#{prefix}", ctrl, "create", path)
        when "update"
          routes << Route.new("PUT", "/#{prefix}/:id", ctrl, "update", path)
          routes << Route.new("PATCH", "/#{prefix}/:id", ctrl, "update", path)
        when "destroy"
          routes << Route.new("DELETE", "/#{prefix}/:id", ctrl, "destroy", path)
        end
      end
    end

    parse_resource_actions = lambda do |line|
      actions = rest_actions_default.dup
      if line =~ /only:\s*\[([^\]]+)\]/
        actions = $1.scan(/:[a-zA-Z0-9_]+/).map { |t| normalize_token(t) }.reject(&:empty?)
        actions &= rest_actions_default + %w[new edit]
      elsif line =~ /only:\s*%i[\(\{]([^\)\}]+)[\)\}]/
        actions = $1.split(/\s+/).grep(/\S/).map { |t| normalize_token(t) }.reject(&:empty?)
        actions &= rest_actions_default + %w[new edit]
      elsif line =~ /except:\s*\[([^\]]+)\]/
        ex = $1.scan(/:[a-zA-Z0-9_]+/).map { |t| normalize_token(t) }
        actions -= ex
      elsif line =~ /except:\s*%i[\(\{]([^\)\}]+)[\)\}]/
        ex = $1.split(/\s+/).grep(/\S/).map { |t| normalize_token(t) }
        actions -= ex
      end
      actions
    end

    singular_actions_default = %w[show new create edit update destroy]

    parse_singular_resource_actions = lambda do |line|
      actions = singular_actions_default.dup
      if line =~ /only:\s*\[([^\]]+)\]/
        actions = $1.scan(/:[a-zA-Z0-9_]+/).map { |t| normalize_token(t) }.reject(&:empty?)
        actions &= singular_actions_default
      elsif line =~ /only:\s*%i[\(\{]([^\)\}]+)[\)\}]/
        actions = $1.split(/\s+/).grep(/\S/).map { |t| normalize_token(t) }.reject(&:empty?)
        actions &= singular_actions_default
      elsif line =~ /except:\s*\[([^\]]+)\]/
        ex = $1.scan(/:[a-zA-Z0-9_]+/).map { |t| normalize_token(t) }
        actions -= ex
      elsif line =~ /except:\s*%i[\(\{]([^\)\}]+)[\)\}]/
        ex = $1.split(/\s+/).grep(/\S/).map { |t| normalize_token(t) }
        actions -= ex
      end
      actions
    end

    emit_singular_rest_routes = lambda do |path_seg, _res_name, ctrl|
      prefix = [path_prefix.call, path_seg].reject(&:empty?).join("/")
      base = "/#{prefix}"
      routes << Route.new("GET", "#{base}/new", ctrl, "new", path)
      routes << Route.new("GET", "#{base}/edit", ctrl, "edit", path)
      routes << Route.new("GET", base, ctrl, "show", path)
      routes << Route.new("POST", base, ctrl, "create", path)
      routes << Route.new("PUT", base, ctrl, "update", path)
      routes << Route.new("PATCH", base, ctrl, "update", path)
      routes << Route.new("DELETE", base, ctrl, "destroy", path)
    end

    emit_singular_rest_routes_filtered = lambda do |path_seg, _res_name, ctrl, actions|
      prefix = [path_prefix.call, path_seg].reject(&:empty?).join("/")
      base = "/#{prefix}"
      actions.each do |act|
        case act
        when "show"
          routes << Route.new("GET", base, ctrl, "show", path)
        when "new"
          routes << Route.new("GET", "#{base}/new", ctrl, "new", path)
        when "edit"
          routes << Route.new("GET", "#{base}/edit", ctrl, "edit", path)
        when "create"
          routes << Route.new("POST", base, ctrl, "create", path)
        when "update"
          routes << Route.new("PUT", base, ctrl, "update", path)
          routes << Route.new("PATCH", base, ctrl, "update", path)
        when "destroy"
          routes << Route.new("DELETE", base, ctrl, "destroy", path)
        end
      end
    end

    resource_url_segment = lambda do |line, res_name|
      if line =~ /path:\s*['"]([^'"]+)['"]/
        $1
      else
        res_name
      end
    end

    lines.each_with_index do |raw, ln|
      line = raw.strip
      # skip comments and blank
      next if line.start_with?("#") || line.empty?

      # namespace :api do  |  namespace :api, path: 'v1' do
      if line =~ /^namespace\s+:?([a-zA-Z0-9_]+)/
        ns = $1.to_s
        ns_path = nil
        ns_path = $1 if line =~ /path:\s*['"]([^'"]+)['"]/
        stack << { type: :ns, name: ns, path: ns_path }
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

      # root to: 'welcome#index' | root 'welcome#index'
      if line =~ /^root\s+to:\s*['"]([^'"]+)#([^'"]+)['"]/ ||
         line =~ /^root\s+['"]([^'"]+)#([^'"]+)['"]/
        controller_raw = $1
        action = $2
        ctrl = controller_string_to_controller_class(controller_raw, controller_prefix.call)
        pre = path_prefix.call
        full_path = pre.empty? ? "/" : "/#{pre}"
        routes << Route.new("GET", full_path, ctrl, action, path)
        next
      end

      # resource :profile (singular) — paths sem :id em show/edit/update/destroy
      if line =~ /^resource\s+:?([a-zA-Z0-9_]+)/
        res = $1.to_s
        path_seg = resource_url_segment.call(line, res)
        code_line = line.sub(/#.*/, "")
        has_do = code_line.strip.end_with?(" do")

        ctrl = build_controller_name(controller_prefix.call, res)
        if has_do
          if code_line.match?(/only:|except:/)
            actions = parse_singular_resource_actions.call(line)
            emit_singular_rest_routes_filtered.call(path_seg, res, ctrl, actions)
          end
          stack << {
            type: :res_singular,
            base: res,
            controller: res,
            controller_class: ctrl,
            url_segment: path_seg
          }
        else
          actions = parse_singular_resource_actions.call(line)
          if actions == singular_actions_default && !line.match?(/only:|except:/)
            emit_singular_rest_routes.call(path_seg, res, ctrl)
          else
            emit_singular_rest_routes_filtered.call(path_seg, res, ctrl, actions)
          end
        end
        next
      end

      # resources :users do / resources :users / resources :posts, only: [:index]
      if line =~ /^resources\s+:?([a-zA-Z0-9_]+)/
        res = $1.to_s
        path_seg = resource_url_segment.call(line, res)
        code_line = line.sub(/#.*/, "")
        has_do = code_line.strip.end_with?(" do")

        if has_do
          ctrl = build_controller_name(controller_prefix.call, res)
          if code_line.match?(/only:|except:/)
            actions = parse_resource_actions.call(line)
            emit_rest_routes_filtered.call(path_seg, res, ctrl, actions)
          end
          stack << {
            type: :res,
            base: res,
            controller: res,
            controller_class: ctrl,
            url_segment: path_seg
          }
        else
          ctrl = build_controller_name(controller_prefix.call, res)
          actions = parse_resource_actions.call(line)
          if actions == rest_actions_default && !line.match?(/only:|except:/)
            emit_rest_routes.call(path_seg, res, ctrl)
          else
            emit_rest_routes_filtered.call(path_seg, res, ctrl, actions)
          end
        end
        next
      end

      # end of block
      if line == "end"
        stack.pop
        next
      end

      # direct HTTP route: get 'path', to: 'controller#action'
      if line =~ /^(get|post|put|patch|delete|options)\s+['"]([^'"]+)['"],\s*to:\s*['"]([^'"]+)#([^'"]+)['"]/
        verb = $1.upcase
        path_suffix = $2
        controller_raw = $3
        action = $4

        # controller may be namespaced in string like 'sales/api/v1/reservations'
        ctrl = controller_string_to_controller_class(controller_raw, controller_prefix.call)

        full_path = route_full_path.call(path_suffix)

        routes << Route.new(verb, full_path, ctrl, action, path)
        next
      end

      # post 'trips/operator/:operator_id', to: 'trips#operator'
      if line =~ /^(get|post|put|patch|delete|options)\s+['"]([^'"]+)['"]\s*,\s*to:\s*['"]([^'"]+)#([^'"]+)['"]/
        verb = $1.upcase
        path_suffix = $2
        controller_raw = $3
        action = $4
        ctrl = controller_string_to_controller_class(controller_raw, controller_prefix.call)
        full_path = route_full_path.call(path_suffix)
        routes << Route.new(verb, full_path, ctrl, action, path)
        next
      end

      # route with controller#action variable style: match 'path', to: 'controller#action', via: :get
      if line =~ /^match\s+['"]([^'"]+)['"]\s*,\s*to:\s*['"]([^'"]+)#([^'"]+)['"]\s*,\s*via:\s*:?(get|post|put|patch|delete|options)/
        path_suffix = $1
        controller_raw = $2
        action = $3
        verb = $4.upcase
        ctrl = controller_string_to_controller_class(controller_raw, controller_prefix.call)
        full_path = route_full_path.call(path_suffix)
        routes << Route.new(verb, full_path, ctrl, action, path)
        next
      end

      # member routes inside resources blocks like: member do; get :preview; end
      # we'll detect lines like get :preview
      if line =~ /^(get|post|put|patch|delete|options)\s+:?([a-zA-Z0-9_]+)/
        verb = $1.upcase
        action = $2.to_s
        # try find last :res or :res_singular in stack
        res = stack.reverse.find { |s| s[:type] == :res || s[:type] == :res_singular }
        if res
          url_base = res[:url_segment] || res[:base]
          ctrl = res[:controller_class] || build_controller_name(controller_prefix.call, res[:base])
        full_path = route_full_path.call([url_base, action].join("/"))
          routes << Route.new(verb, full_path, ctrl, action, path)
        end
        next
      end

      # custom: direct to 'controller#action' inside resources member: put 'cancel', to: 'reservations#cancel'
      if line =~ /^(get|post|put|patch|delete|options)\s+['"]([^'"]+)['"]\s*,\s*to:\s*['"]([^'"]+)#([^'"]+)['"]/
        verb = $1.upcase
        path_suffix = $2
        controller_raw = $3
        action = $4
        
        # Se estiver dentro de um bloco resources, usar o controller atual do contexto
        res = stack.reverse.find { |s| s[:type] == :res || s[:type] == :res_singular }
        if res && controller_raw == res[:base]
          # Mesmo controller do resource atual
          ctrl = build_controller_name(controller_prefix.call, controller_raw)
        else
          # Controller diferente, aplicar namespace normalmente
          ctrl = controller_string_to_controller_class(controller_raw, controller_prefix.call)
        end
        
        full_path = route_full_path.call(path_suffix)
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
