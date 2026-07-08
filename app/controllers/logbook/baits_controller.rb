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
    @vocab = chip_vocab
  end

  # JSON is the catch form's quick-add panel: it fetch-POSTs here mid-catch
  # and slots the returned {id, name} straight into the bait dropdown.
  def create
    @bait = current_user.baits.build(bait_params)
    if @bait.save
      respond_to do |format|
        format.html { redirect_to logbook_baits_path, notice: "Bait added." }
        format.json { render json: { id: @bait.id, name: @bait.display_name }, status: :created }
      end
    else
      respond_to do |format|
        format.html do
          flash.now[:alert] = @bait.errors.full_messages.to_sentence
          @vocab = chip_vocab
          render :new, status: :unprocessable_entity
        end
        format.json { render json: { errors: @bait.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def edit
    @vocab = chip_vocab
  end

  def update
    if @bait.update(bait_params)
      redirect_to logbook_baits_path, notice: "Bait updated."
    else
      flash.now[:alert] = @bait.errors.full_messages.to_sentence
      @vocab = chip_vocab
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
    params.require(:bait).permit(:color, :weight, :lure_type, :bait_type, :plastic, :plastic_color)
  end

  def chip_vocab
    Bait.chip_vocab(current_user)
  end

  def ensure_logbook_enabled
    return if logbook_enabled?
    redirect_to root_path, alert: "Logbook isn't enabled on this server."
  end
end
