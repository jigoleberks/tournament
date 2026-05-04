module Geofence
  REGIONS = {
    lake: "lake.json",
    sask: "sask.json"
  }.freeze

  class UnknownRegion < ArgumentError; end

  module_function

  def includes?(region, latitude, longitude)
    polygon = polygon(region) # raises UnknownRegion before we touch coords
    return false if latitude.nil? || longitude.nil?
    point_in_polygon?(longitude.to_f, latitude.to_f, polygon)
  end

  def polygon(region)
    @polygons ||= {}
    @polygons[region] ||= load_polygon(region)
  end

  def reload!
    @polygons = nil
  end

  def load_polygon(region)
    file = REGIONS.fetch(region) { raise UnknownRegion, region.inspect }
    geojson = JSON.parse(File.read(Rails.root.join("geofence", file)))
    geojson.fetch("features").first.fetch("geometry").fetch("coordinates").first
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
