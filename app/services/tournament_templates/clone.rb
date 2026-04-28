module TournamentTemplates
  class Clone
    def self.call(template:, starts_at:, ends_at: nil, name: nil, season_tag: nil)
      ActiveRecord::Base.transaction do
        tournament = template.club.tournaments.create!(
          name: name || template.name,
          kind: :event,
          mode: template.mode,
          starts_at: starts_at,
          ends_at: ends_at,
          season_tag: season_tag,
          template_source_id: template.id
        )
        template.tournament_template_scoring_slots.each do |slot|
          tournament.scoring_slots.create!(species: slot.species, slot_count: slot.slot_count)
        end
        tournament
      end
    end
  end
end
