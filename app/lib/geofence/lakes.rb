module Geofence
  module Lakes
    KIND_ORDER = { "lake" => 0, "river" => 1 }.freeze
    MUTEX = Mutex.new

    module_function

    def all
      data[:entries]
    end

    def known_key?(key)
      return false if key.nil?
      data[:keys].include?(key)
    end

    def match(latitude, longitude)
      return nil if latitude.nil? || longitude.nil?
      x = longitude.to_f
      y = latitude.to_f
      data[:polygons].each do |key, polys|
        polys.each do |bbox, rings|
          next if x < bbox[0] || x > bbox[2] || y < bbox[1] || y > bbox[3]
          outer, *holes = rings
          next unless ::Geofence.point_in_polygon?(x, y, outer)
          next if holes.any? { |h| ::Geofence.point_in_polygon?(x, y, h) }
          return key
        end
      end
      nil
    end

    def reload!
      MUTEX.synchronize { @data = nil }
    end

    def load!
      data
      nil
    end

    # Single-ivar snapshot so concurrent readers either see the previous fully-
    # built hash or the new one — never a half-loaded state. The fast path
    # avoids the mutex once @data is set.
    def data
      @data || MUTEX.synchronize { @data ||= build }
    end

    def build
      raw = Dir[Rails.root.join("geofence/lakes/*.json")].map do |path|
        key = File.basename(path, ".json")
        if key == "all" || key == "other"
          raise ArgumentError,
                "Reserved key collision: geofence/lakes/#{key}.json conflicts with the 'all'/'other' filter sentinels"
        end
        feat = JSON.parse(File.read(path)).fetch("features").first
        props = feat.fetch("properties")
        {
          key:      key,
          name:     props.fetch("name"),
          kind:     props.fetch("kind"),
          polygons: parse_polygons(feat.fetch("geometry")).map { |rings| [bbox_of(rings.first), rings].freeze },
        }
      end

      sorted = raw.sort_by { |r| [KIND_ORDER[r[:kind]] || 99, r[:name]] }

      {
        polygons: sorted.map { |r| [r[:key], r[:polygons]] }.freeze,
        entries:  sorted.map { |r| { key: r[:key], name: r[:name], kind: r[:kind] }.freeze }.freeze,
        keys:     sorted.map { |r| r[:key] }.to_set.freeze,
      }.freeze
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

    # Precomputed outer-ring bbox lets match() skip the ray-cast for the common
    # case of a catch nowhere near a given polygon (Mainprize alone has ~35k vertices).
    def bbox_of(ring)
      min_x = max_x = ring[0][0]
      min_y = max_y = ring[0][1]
      ring.each do |(x, y)|
        min_x = x if x < min_x
        max_x = x if x > max_x
        min_y = y if y < min_y
        max_y = y if y > max_y
      end
      [min_x, min_y, max_x, max_y].freeze
    end
  end
end
