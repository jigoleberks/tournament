class Admin::Clubs::BannersController < Admin::Clubs::BaseController
  def edit
    @memberships = club_memberships
  end

  def update
    selected_ids = Array(params[:member_ids]).map(&:to_i)
    Club.transaction do
      @foreign_club.update!(banner_params)
      memberships = @foreign_club.club_memberships
      memberships.where(user_id: selected_ids).update_all(show_banner: true)
      memberships.where.not(user_id: selected_ids).update_all(show_banner: false)
    end
    redirect_to admin_club_path(@foreign_club), notice: "Banner updated."
  rescue ActiveRecord::RecordInvalid
    @memberships = club_memberships
    render :edit, status: :unprocessable_entity
  end

  private

  def club_memberships
    @foreign_club.club_memberships.joins(:user).includes(:user).order("users.name")
  end

  def banner_params
    params.require(:club).permit(:banner_message, :banner_style)
  end
end
