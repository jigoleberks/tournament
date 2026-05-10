module TournamentTemplates
  class Clone
    def self.call(template:, starts_at:, ends_at: nil, name: nil, season_tag: nil)
      ActiveRecord::Base.transaction do
        slots_attrs = template.tournament_template_scoring_slots.map do |slot|
          { species_id: slot.species_id, slot_count: slot.slot_count }
        end
        tournament = template.club.tournaments.create!(
          name: name || template.name,
          kind: :event,
          mode: template.mode,
          format: template.format,
          train_cars: template.train_cars,
          starts_at: starts_at,
          ends_at: ends_at,
          season_tag: season_tag,
          template_source_id: template.id,
          awards_season_points: template.awards_season_points,
          blind_leaderboard: template.blind_leaderboard,
          scoring_slots_attributes: slots_attrs
        )
        tournament
      end
    end
  end
end
