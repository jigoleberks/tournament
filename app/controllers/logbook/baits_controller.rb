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

  def create
    @bait = current_user.baits.build(bait_params)
    if @bait.save
      redirect_to logbook_baits_path, notice: "Bait added."
    else
      flash.now[:alert] = @bait.errors.full_messages.to_sentence
      @vocab = chip_vocab
      render :new, status: :unprocessable_entity
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

  # Starter chips shown before the angler has built up their own vocabulary.
  STARTER_VOCAB = {
    colors:   ["white", "chartreuse", "orange", "pink", "blue", "green"],
    lures:    ["jighead", "fireball"],
    plastics: ["twister grub", "tube jig", "frog"],
    tippings: ["minnow", "crawler", "leech"]
  }.freeze

  # Tap-chip options per attribute: everything this user has ever entered
  # (archived combos included — retiring a combo shouldn't shrink the
  # vocabulary), merged with the starters, deduped case-insensitively.
  def chip_vocab
    baits = current_user.baits
    {
      colors:   merged_vocab(:colors, baits.pluck(:color) + baits.pluck(:plastic_color)),
      lures:    merged_vocab(:lures, baits.pluck(:lure_type)),
      plastics: merged_vocab(:plastics, baits.pluck(:plastic)),
      tippings: merged_vocab(:tippings, baits.pluck(:bait_type))
    }
  end

  def merged_vocab(key, values)
    (values.map { |v| v.to_s.strip }.reject(&:blank?) + STARTER_VOCAB[key])
      .uniq(&:downcase)
  end

  def ensure_logbook_enabled
    return if logbook_enabled?
    redirect_to root_path, alert: "Logbook isn't enabled on this server."
  end
end
