class UsersController < ApplicationController
  before_action :require_sign_in!

  def update
    if current_user.update(length_unit: params.require(:user).permit(:length_unit)[:length_unit])
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path, notice: "Preferences saved." }
        format.json { head :no_content }
      end
    else
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path, alert: current_user.errors.full_messages.to_sentence }
        format.json { render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end
end
