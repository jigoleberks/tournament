class Organizers::MembersController < Organizers::BaseController
  def index
    @users = current_user.club.users.order(:deactivated_at, :name)
  end

  def new
    @user = current_user.club.users.new
  end

  def create
    @user = current_user.club.users.new(user_params)
    role_for_membership = user_params[:role].presence || "member"
    saved = false
    begin
      ActiveRecord::Base.transaction do
        @user.save!
        ClubMembership.create!(user: @user, club: current_user.club, role: role_for_membership)
      end
      saved = true
    rescue ActiveRecord::RecordInvalid
      # AR rolled back the user INSERT. If User#save! is what failed, @user.errors
      # is populated and the form will show them. If it was ClubMembership.create!
      # (e.g. a future model validation we haven't anticipated here), @user.errors
      # is empty — surface a generic message so the form isn't silent.
      @user.errors.add(:base, "Couldn't send the invite. Please try again.") if @user.errors.empty?
    end
    if saved
      token = SignInToken.issue!(user: @user, club: current_user.club, ttl: 7.days)
      InvitationMailer.welcome(token).deliver_later
      redirect_to organizers_members_path, notice: "Invite sent."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    user = current_user.club.users.find(params[:id])
    if user == current_user
      redirect_to organizers_members_path, alert: "You can't deactivate yourself."
    else
      user.update!(deactivated_at: Time.current)
      redirect_to organizers_members_path, notice: "#{user.name} deactivated."
    end
  end

  def reactivate
    user = current_user.club.users.find(params[:id])
    user.update!(deactivated_at: nil)
    redirect_to organizers_members_path, notice: "#{user.name} reactivated."
  end

  def issue_code
    member = current_user.club.users.active.find(params[:id])
    token = SignInToken.issue_code!(user: member, club: current_user.club)
    flash[:code] = token.token
    redirect_to code_organizers_member_path(member), status: :see_other
  end

  def code
    @member = current_user.club.users.find(params[:id])
    @code = flash[:code]
    redirect_to organizers_members_path and return unless @code
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :role)
  end
end
