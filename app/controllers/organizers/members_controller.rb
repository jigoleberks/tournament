class Organizers::MembersController < Organizers::BaseController
  def index
    @users = current_user.club.users.order(:name)
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

  private

  def user_params
    params.require(:user).permit(:name, :email, :role)
  end
end
