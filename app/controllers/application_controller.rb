class ApplicationController < ActionController::Base
  include Authentication
  allow_browser versions: :modern

  before_action :touch_last_seen

  private

  def touch_last_seen
    current_user&.touch_last_seen!
  end
end
