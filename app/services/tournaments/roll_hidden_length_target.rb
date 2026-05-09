module Tournaments
  class RollHiddenLengthTarget
    QUARTER_INCH_STEPS = (0..40).map { |i| BigDecimal("12.00") + BigDecimal("0.25") * i }.freeze

    def self.call(tournament:)
      tournament.with_lock do
        if tournament.hidden_length_target.present?
          return { target: tournament.hidden_length_target, already_rolled: true }
        end
        tournament.update!(hidden_length_target: QUARTER_INCH_STEPS.sample)
      end
      Placements::BroadcastLeaderboard.call(tournament: tournament)
      { target: tournament.hidden_length_target, already_rolled: false }
    end
  end
end
