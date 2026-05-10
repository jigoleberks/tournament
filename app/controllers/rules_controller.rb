class RulesController < ApplicationController
  before_action :require_sign_in!

  def show
    @revision = current_club&.current_rules_revision
  end
end
