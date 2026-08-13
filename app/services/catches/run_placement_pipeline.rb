module Catches
  # The post-save pipeline shared by the API (first saves AND dedup retries
  # whose first run crashed part-way — see Api::CatchesController) and the
  # web form (CatchesController#create). Every step is idempotent, so a
  # re-run is safe: PlaceInSlots skips already-placed tournaments and
  # add_flag! is a guarded single UPDATE. Returns the PlaceInSlots result.
  class RunPlacementPipeline
    def self.call(catch:)
      placements = PlaceInSlots.call(catch: catch)
      FlagDuplicates.call(catch: catch) if catch.flags.include?("possible_duplicate")
      ::FetchCatchConditionsJob.perform_later(catch_id: catch.id)
      ::FlagImportedPhotoJob.perform_later(catch_id: catch.id)
      # Stamped LAST: a crash anywhere above leaves it nil, so the API's dedup
      # retry knows to re-run the pipeline.
      catch.update_column(:placements_evaluated_at, Time.current)
      placements
    end
  end
end
