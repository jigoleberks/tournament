class Admin::ClubsController < ApplicationController
  layout "admin"
  before_action :require_sign_in!
  before_action :require_admin!
  before_action :set_club, only: [ :edit, :update, :show ]

  def index
    @clubs = Club.left_joins(:club_memberships, :tournaments)
                 .group("clubs.id")
                 .select("clubs.*, COUNT(DISTINCT club_memberships.user_id) AS user_count, COUNT(DISTINCT tournaments.id) AS tournament_count")
                 .order(:name)
  end

  def show
    @foreign_club            = @club
    @member_count            = @club.members.count
    @tournament_count        = @club.tournaments.count
    @active_tournament_count = @club.tournaments.active_at(Time.current).count
    @catch_count             = Catch.where(user_id: @club.members.select(:id))
                                    .count
  end

  def new
    @club = Club.new
  end

  def create
    @club = Club.new(club_params)
    if @club.save
      redirect_to admin_clubs_path, notice: "#{@club.name} created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @club.update(club_params)
      redirect_to admin_clubs_path, notice: "#{@club.name} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_club
    @club = Club.find(params[:id])
  end

  def club_params
    params.require(:club).permit(:name)
  end

  def require_admin!
    head :forbidden unless current_user&.admin?
  end
end
