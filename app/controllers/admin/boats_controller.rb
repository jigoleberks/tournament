class Admin::BoatsController < Admin::BaseController
  def index
    @boats = current_club.boats.active.alphabetical
  end

  def enter
    tournament = current_club.tournaments.find(params[:tournament_id])
    unless tournament.mode_team?
      redirect_to edit_admin_tournament_path(tournament), alert: "Boats are for team tournaments." and return
    end
    boat = current_club.boats.find(params[:id])
    ::Boats::Enter.call(tournament: tournament, boat: boat)
    redirect_to edit_admin_tournament_path(tournament), notice: "#{boat.name} entered."
  end

  def create
    tournament = current_club.tournaments.find(params[:tournament_id])
    name = params.dig(:boat, :name)

    if (match = ::Boats::NearMatch.call(club: current_club, name: name))
      redirect_to edit_admin_tournament_path(tournament),
                  alert: "Did you mean #{match.name}? Tap it in the list to enter it." and return
    end

    boat = current_club.boats.new(name: name, captain_user_id: params.dig(:boat, :captain_user_id))
    if boat.save
      ::Boats::Enter.call(tournament: tournament, boat: boat)
      redirect_to edit_admin_tournament_path(tournament), notice: "#{boat.name} entered."
    else
      redirect_to edit_admin_tournament_path(tournament), alert: boat.errors.full_messages.to_sentence
    end
  end

  def update
    boat = current_club.boats.find(params[:id])
    if boat.update(name: params.dig(:boat, :name), captain_user_id: params.dig(:boat, :captain_user_id))
      redirect_to admin_boats_path, notice: "Boat updated."
    else
      redirect_to admin_boats_path, alert: boat.errors.full_messages.to_sentence
    end
  end

  def destroy
    boat = current_club.boats.find(params[:id])
    boat.update!(active: false)
    redirect_to admin_boats_path, notice: "#{boat.name} retired."
  end
end
