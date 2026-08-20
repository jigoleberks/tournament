class Admin::Clubs::SeasonPointsController < Admin::Clubs::BaseController
  # Field sizes shown in the preview table — one per band, derived from
  # Club::SEASON_POINTS_BANDS (see Club.season_points_bands) so this can't
  # drift out of sync with the labels or with the member-facing explainer.
  # Set on every action, not just #edit, since #update re-renders :edit on
  # both failure paths.
  before_action :set_preview_field_sizes

  def edit
  end

  def update
    @foreign_club.assign_attributes(season_points_params)
    if @foreign_club.save
      redirect_to admin_club_path(@foreign_club), notice: "Season points updated."
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ArgumentError
    # An out-of-range scheme (the radios are bypassable) raises on enum
    # assignment before any validation runs. Nothing is persisted; re-render.
    @foreign_club.errors.add(:season_points_scheme, "isn't a scheme we know")
    render :edit, status: :unprocessable_entity
  end

  private

  def set_preview_field_sizes
    @preview_field_sizes = Club.season_points_bands.map { |band| band[:sample] }
  end

  def season_points_params
    params.require(:club).permit(
      :season_points_scheme,
      :season_points_attendance,
      :season_points_min_entries,
      :season_points_base_ladder_text,
      :season_points_tier_multipliers_text,
      season_points_ladders_text: []
    )
  end
end
