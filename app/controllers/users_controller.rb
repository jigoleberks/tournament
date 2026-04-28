class UsersController < ApplicationController
  before_action :require_sign_in!

  def update
    if current_user.update(length_unit: params.require(:user).permit(:length_unit)[:length_unit])
      redirect_back fallback_location: root_path, notice: "Preferences saved."
    else
      redirect_back fallback_location: root_path, alert: current_user.errors.full_messages.to_sentence
    end
  end
end
