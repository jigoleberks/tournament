module Tournaments
  class RollHiddenLengthTarget
    QUARTER_INCH_STEPS = (0..40).map { |i| BigDecimal("12.00") + BigDecimal("0.25") * i }.freeze

    # Rolls the target only. Broadcasting the leaderboard is the caller's job —
    # decoupled so the lifecycle job can re-broadcast on retry if the broadcast
    # fails after this row commits, without re-rolling.
    def self.call(tournament:)
      tournament.with_lock do
        if tournament.hidden_length_target.present?
          return { target: tournament.hidden_length_target, already_rolled: true }
        end
        tournament.update!(hidden_length_target: QUARTER_INCH_STEPS.sample)
      end
      { target: tournament.hidden_length_target, already_rolled: false }
    end
  end
end
