class Admin::Clubs::SeasonPointsController < Admin::Clubs::BaseController
  # Field sizes shown in the preview table — one per band, so an admin can see
  # what a small, medium, large and very large night pays before saving.
  PREVIEW_FIELD_SIZES = [6, 14, 24, 34].freeze

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
    @foreign_club.reload
    @foreign_club.errors.add(:season_points_scheme, "isn't a scheme we know")
    render :edit, status: :unprocessable_entity
  end

  private

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
