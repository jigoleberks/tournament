module Boats
  # Finds an existing boat whose name is "the same name typed differently" —
  # case, surrounding or repeated whitespace, or a leading "Team ". This is what
  # keeps Majestic Red / Magestic Red / Team Magestic Red from becoming three
  # boats, which is exactly what happened in the season already on record.
  class NearMatch
    def self.call(club:, name:)
      key = normalize(name)
      return nil if key.blank?
      club.boats.detect { |boat| normalize(boat.name) == key }
    end

    def self.normalize(name)
      name.to_s.downcase.gsub(/\s+/, " ").strip.sub(/\Ateam /, "").sub(/\Athe /, "")
    end
  end
end
