module Boats
  # Finds an existing boat whose name is "the same name typed differently" —
  # case, surrounding or repeated whitespace, or a leading "Team ". This is what
  # keeps Majestic Red / Magestic Red / Team Magestic Red from becoming three
  # boats, which is exactly what happened in the season already on record.
  #
  # Active boats only: a retired boat must not resurface as a suggestion, so a
  # differently-spelled new boat can still be created after one is retired.
  # An EXACT name collision with a retired boat is a different case — the name
  # index spans retired boats — and the boats controllers handle it after the
  # save fails, pointing at Restore rather than at a bare uniqueness error.
  class NearMatch
    def self.call(club:, name:)
      key = normalize(name)
      return nil if key.blank?
      club.boats.active.detect { |boat| normalize(boat.name) == key }
    end

    def self.normalize(name)
      name.to_s.downcase.gsub(/\s+/, " ").strip.sub(/\Ateam /, "").sub(/\Athe /, "")
    end
  end
end
