class Admin::Clubs::MembersController < Admin::Clubs::BaseController
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
        ClubMembership.create!(user: @user, club: @foreign_club, role: role_for_membership)
      end
      saved = true
    rescue ActiveRecord::RecordInvalid
      # falls through with saved=false; AR rolled back the user INSERT.
    end
    if saved
      token = SignInToken.issue!(user: @user, club: @foreign_club, ttl: 7.days)
      InvitationMailer.welcome(token).deliver_later
      redirect_to admin_clubs_path, notice: "Invite sent to #{@user.email} for #{@foreign_club.name}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def issue_code
    member = @foreign_club.members.active.find(params[:id])
    token = SignInToken.issue_code!(user: member, club: @foreign_club)
    flash[:code] = token.token
    redirect_to code_admin_club_foreign_member_path(@foreign_club, member), status: :see_other
  end

  def code
    @member = @foreign_club.members.active.find(params[:id])
    @code = flash[:code]
    redirect_to admin_club_foreign_members_path(@foreign_club) and return unless @code
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :role)
  end
end
