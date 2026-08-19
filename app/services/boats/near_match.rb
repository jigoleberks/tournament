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
    # except: the boat being renamed. Without it a rename would always match
    # itself and every rename would be refused; with it, #update can run the
    # same guard #create does.
    def self.call(club:, name:, except: nil)
      key = normalize(name)
      return nil if key.blank?
      scope = club.boats.active
      scope = scope.where.not(id: except.id) if except&.id
      scope.detect { |boat| normalize(boat.name) == key }
    end

    def self.normalize(name)
      name.to_s.downcase.gsub(/\s+/, " ").strip.sub(/\Ateam /, "").sub(/\Athe /, "")
    end
  end
end
