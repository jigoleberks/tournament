module Geofence
  module Lakes
    KIND_ORDER = { "lake" => 0, "river" => 1 }.freeze

    module_function

    def all
      load!
      @entries
    end

    def match(latitude, longitude)
      return nil if latitude.nil? || longitude.nil?
      load!
      x = longitude.to_f
      y = latitude.to_f
      @polygons.each do |key, polys|
        polys.each do |rings|
          outer, *holes = rings
          next unless ::Geofence.point_in_polygon?(x, y, outer)
          next if holes.any? { |h| ::Geofence.point_in_polygon?(x, y, h) }
          return key
        end
      end
      nil
    end

    def reload!
      @entries = nil
      @polygons = nil
    end

    def load!
      return if @entries

      raw = Dir[Rails.root.join("geofence/lakes/*.json")].map do |path|
        key  = File.basename(path, ".json")
        feat = JSON.parse(File.read(path)).fetch("features").first
        props = feat.fetch("properties")
        {
          key:      key,
          name:     props.fetch("name"),
          kind:     props.fetch("kind"),
          polygons: parse_polygons(feat.fetch("geometry")),
        }
      end

      sorted = raw.sort_by { |r| [KIND_ORDER[r[:kind]] || 99, r[:name]] }

      @entries  = sorted.map { |r| { key: r[:key], name: r[:name], kind: r[:kind] } }
      @polygons = sorted.map { |r| [r[:key], r[:polygons]] }
    end

    # Returns an array of polygons, where each polygon is [outer_ring, *hole_rings].
    # Each ring is an array of [lng, lat] pairs.
    def parse_polygons(geom)
      case geom.fetch("type")
      when "Polygon"
        [geom.fetch("coordinates")]
      when "MultiPolygon"
        geom.fetch("coordinates")
      else
        raise ArgumentError, "Unsupported geometry type: #{geom['type'].inspect}"
      end
    end
  end
end
