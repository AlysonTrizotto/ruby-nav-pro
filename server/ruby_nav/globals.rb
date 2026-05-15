# ================================================================
# Global indexes
# ================================================================
@index      = Hash.new { |h, k| h[k] = [] }
@const_map  = {}
@relations  = Hash.new { |h, k| h[k] = Set.new }
@references = Hash.new { |h, k| h[k] = [] }
@instance_methods = Hash.new { |h, k| h[k] = [] } # Métodos de instância por classe
@const_by_short = Hash.new { |h, k| h[k] = [] }   # Mapeia nome curto -> nomes completos
