module Geofence
  POLYGON_PATH = Rails.root.join("geofence", "lake.json").freeze

  module_function

  def includes?(latitude, longitude)
    return false if latitude.nil? || longitude.nil?
    point_in_polygon?(longitude.to_f, latitude.to_f, polygon)
  end

  def polygon
    @polygon ||= load_polygon
  end

  def reload!
    @polygon = nil
    polygon
  end

  def load_polygon
    geojson = JSON.parse(File.read(POLYGON_PATH))
    feature = geojson.fetch("features").first
    feature.fetch("geometry").fetch("coordinates").first
  end

  # Ray-casting algorithm. Counts edge crossings on a horizontal ray east from
  # the point; odd = inside. Polygon is an array of [lng, lat] pairs.
  def point_in_polygon?(x, y, ring)
    inside = false
    j = ring.length - 1
    ring.each_with_index do |(xi, yi), i|
      xj, yj = ring[j]
      if ((yi > y) != (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi).to_f + xi)
        inside = !inside
      end
      j = i
    end
    inside
  end
end
