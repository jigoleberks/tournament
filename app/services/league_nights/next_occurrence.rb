module LeagueNights
  # Works out which night the scheduler is about to create, and whether any of
  # it already exists. "Already scheduled" is keyed off template_source_id and
  # the date, so a half-night — a Main with no Side, which has happened — is
  # detected as such rather than looking untouched.
  class NextOccurrence
    Result = Struct.new(
      :starts_at, :ends_at, :main_template, :side_template, :existing_main, :existing_side,
      keyword_init: true
    ) do
      def fully_scheduled?
        existing_main.present? && existing_side.present?
      end

      def partially_scheduled?
        existing_main.present? ^ existing_side.present?
      end
    end

    def self.call(template:, now: Time.zone.now, on: nil)
      new(template: template, now: now, on: on).call
    end

    # on: names the night explicitly (a Date) instead of rolling forward to the
    # next matching weekday. Repairing an already-run half-night — 2026-08-06
    # was a Main with no Side — means naming a date in the PAST, which
    # next_occurrence_at can never return, so without this the half that exists
    # is never detected and the scheduler would build a duplicate of it.
    # #create passes the date it is actually building on for the same reason.
    # Nil restores the plain "next occurrence" behaviour.
    def initialize(template:, now:, on: nil)
      @template = template
      @now = now
      @on = on
    end

    def call
      starts_at, ends_at = resolve_window
      partner = @template.paired_template

      Result.new(
        starts_at: starts_at,
        ends_at: ends_at,
        main_template: @template,
        side_template: partner,
        existing_main: scheduled_from(@template, starts_at),
        existing_side: partner && scheduled_from(partner, starts_at)
      )
    end

    private

    # Both branches return nil when the template has no weekday/times at all,
    # so the screen's "set a weekday first" state is reached either way.
    def resolve_window
      return @template.next_occurrence_at(now: @now) if @on.nil?
      @template.occurrence_at(@on)
    end

    def scheduled_from(template, starts_at)
      return nil if starts_at.nil?
      # Ordered explicitly: more than one tournament can share a template and a
      # day (a duplicate created by hand, say), and #first would otherwise lean
      # on Rails' implicit primary-key ordering to decide which one the screen
      # calls "the half that already exists".
      ::Tournament.where(template_source_id: template.id)
                  .where(starts_at: starts_at.beginning_of_day..starts_at.end_of_day)
                  .order(:id)
                  .first
    end
  end
end
