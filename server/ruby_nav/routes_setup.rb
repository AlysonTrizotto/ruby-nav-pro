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
