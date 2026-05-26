module Tournaments
  class DrawTaggedWinner
    class NoEligibleCatchesError < StandardError; end

    def self.call(tournament:, drawn_by:, force: false)
      new(tournament: tournament, drawn_by: drawn_by, force: force).call
    end

    def initialize(tournament:, drawn_by:, force:)
      @tournament = tournament
      @drawn_by = drawn_by
      @force = force
    end

    def call
      winning_placement = ActiveRecord::Base.transaction do
        @tournament.lock!
        raise ArgumentError, "tournament format is not 'tagged'"  unless @tournament.format_tagged?
        raise ArgumentError, "tournament has not yet ended"        unless @tournament.ended?
        raise ArgumentError, "already drawn (pass force: true to redraw)" if @tournament.drawn_at.present? && !@force

        eligible = @tournament.catch_placements
                              .where(active: true)
                              .includes(catch: :user)
                              .to_a
        raise NoEligibleCatchesError, "no tagged catches to draw from" if eligible.empty?

        winner = eligible.sample
        @tournament.update!(
          drawn_winning_placement_id: winner.id,
          drawn_at: Time.current,
          drawn_by_user_id: @drawn_by.id
        )
        winner
      end

      # After commit: rebroadcast + notify winner. Outside the transaction so
      # other DB connections see the winner state.
      Placements::BroadcastLeaderboard.call(tournament: @tournament)
      DeliverPushNotificationJob.perform_later(
        user_id: winning_placement.catch.user_id,
        title: "You won the Tagged Walleye draw!",
        body: "Tag #{winning_placement.catch.tag_number} drawn from #{@tournament.name}.",
        url: Rails.application.routes.url_helpers.tournament_path(@tournament),
        tournament_id: @tournament.id
      )

      winning_placement
    end
  end
end
