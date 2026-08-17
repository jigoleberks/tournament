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

    def self.call(template:, now: Time.zone.now)
      new(template: template, now: now).call
    end

    def initialize(template:, now:)
      @template = template
      @now = now
    end

    def call
      starts_at, ends_at = @template.next_occurrence_at(now: @now)
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

    def scheduled_from(template, starts_at)
      return nil if starts_at.nil?
      ::Tournament.where(template_source_id: template.id)
                  .where(starts_at: starts_at.beginning_of_day..starts_at.end_of_day)
                  .first
    end
  end
end
