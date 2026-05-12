class Admin::Clubs::MembersController < ApplicationController
  layout "admin"
  before_action :require_sign_in!
  before_action :require_admin!
  before_action :set_club
  before_action :alias_foreign_club

  def index
    @users = @foreign_club.members.includes(:club_memberships).order(:deactivated_at, :name)
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params.except(:role))
    role_for_membership = user_params[:role].presence || "member"
    saved = false
    begin
      ActiveRecord::Base.transaction do
        @user.save!
        ClubMembership.create!(user: @user, club: @club, role: role_for_membership)
      end
      saved = true
    rescue ActiveRecord::RecordInvalid
      # falls through with saved=false; AR rolled back the user INSERT.
    end
    if saved
      token = SignInToken.issue!(user: @user, club: @club, ttl: 7.days)
      InvitationMailer.welcome(token).deliver_later
      redirect_to admin_clubs_path, notice: "Invite sent to #{@user.email} for #{@club.name}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_club
    @club = Club.find(params[:club_id])
  end

  # Surface @club under the @foreign_club name so the admin layout's
  # "Viewing X — read-only" banner appears on every action in this controller,
  # mirroring the convention used by Admin::Clubs::BaseController.
  def alias_foreign_club
    @foreign_club = @club
  end

  def user_params
    params.require(:user).permit(:name, :email, :role)
  end

  def require_admin!
    head :forbidden unless current_user&.admin?
  end
end
