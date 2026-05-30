class Logbook::BaitsController < ApplicationController
  before_action :require_sign_in!
  before_action :ensure_logbook_enabled
  before_action :set_bait, only: [:edit, :update, :destroy]

  def index
    @active_baits = current_user.baits.active.order(:created_at)
    @archived_baits = current_user.baits.archived.order(:created_at)
  end

  def new
    @bait = current_user.baits.build
  end

  def create
    @bait = current_user.baits.build(bait_params)
    if @bait.save
      redirect_to logbook_baits_path, notice: "Bait added."
    else
      flash.now[:alert] = @bait.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @bait.update(bait_params)
      redirect_to logbook_baits_path, notice: "Bait updated."
    else
      flash.now[:alert] = @bait.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @bait.archive!
    redirect_to logbook_baits_path, notice: "Bait archived."
  end

  private

  def set_bait
    # Scoped to current_user so a hand-crafted id from another angler
    # raises ActiveRecord::RecordNotFound (and Rails returns 404).
    @bait = current_user.baits.find(params[:id])
  end

  def bait_params
    params.require(:bait).permit(:color, :weight, :lure_type, :bait_type)
  end

  def ensure_logbook_enabled
    return if logbook_enabled?
    redirect_to root_path, alert: "Logbook isn't enabled on this server."
  end
end
