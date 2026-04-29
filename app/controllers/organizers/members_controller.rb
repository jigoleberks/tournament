class Organizers::MembersController < Organizers::BaseController
  def index
    @users = current_user.club.users.order(:deactivated_at, :name)
  end

  def new
    @user = current_user.club.users.new
  end

  def create
    @user = current_user.club.users.new(user_params)
    if @user.save
      token = SignInToken.issue!(user: @user, ttl: 7.days)
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
    token = SignInToken.issue_code!(user: member)
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
