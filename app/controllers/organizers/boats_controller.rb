class Organizers::BoatsController < Organizers::BaseController
  def index
    @boats = current_club.boats.includes(:captain).active.alphabetical
    @retired_boats = current_club.boats.includes(:captain).where(active: false).alphabetical
  end

  def enter
    tournament = current_club.tournaments.find(params[:tournament_id])
    unless tournament.mode_team?
      redirect_to edit_organizers_tournament_path(tournament), alert: "Boats are for team tournaments." and return
    end
    boat = current_club.boats.find(params[:id])
    ::Boats::Enter.call(tournament: tournament, boat: boat)
    redirect_to edit_organizers_tournament_path(tournament), notice: "#{boat.name} entered."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_organizers_tournament_path(tournament), alert: e.message
  end

  def create
    tournament = current_club.tournaments.find(params[:tournament_id])
    unless tournament.mode_team?
      redirect_to edit_organizers_tournament_path(tournament), alert: "Boats are for team tournaments." and return
    end
    name = params.dig(:boat, :name)

    if (match = ::Boats::NearMatch.call(club: current_club, name: name))
      if tournament.tournament_entries.exists?(boat_id: match.id)
        redirect_to edit_organizers_tournament_path(tournament), alert: "#{match.name} is already entered." and return
      end
      redirect_to edit_organizers_tournament_path(tournament),
                  alert: "Did you mean #{match.name}? Tap it in the list to enter it." and return
    end

    boat = current_club.boats.new(name: name, captain_user_id: params.dig(:boat, :captain_user_id))
    if boat.save
      ::Boats::Enter.call(tournament: tournament, boat: boat)
      redirect_to edit_organizers_tournament_path(tournament), notice: "#{boat.name} entered."
    elsif (retired = retired_boat_named(name))
      redirect_to organizers_boats_path,
                  alert: "#{retired.name} is retired. Restore it on the Boats screen to enter it."
    else
      redirect_to edit_organizers_tournament_path(tournament), alert: boat.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_organizers_tournament_path(tournament), alert: e.message
  end

  def update
    boat = current_club.boats.find(params[:id])
    if boat.update(name: params.dig(:boat, :name), captain_user_id: params.dig(:boat, :captain_user_id))
      ::Boats::RenameEntries.call(boat: boat)
      redirect_to organizers_boats_path, notice: "Boat updated."
    else
      redirect_to organizers_boats_path, alert: boat.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to organizers_boats_path, alert: e.message
  end

  def destroy
    boat = current_club.boats.find(params[:id])
    boat.update!(active: false)
    redirect_to organizers_boats_path, notice: "#{boat.name} retired."
  end

  def restore
    boat = current_club.boats.find(params[:id])
    boat.update!(active: true)
    redirect_to organizers_boats_path, notice: "#{boat.name} restored."
  end

  private

  # Boat name uniqueness spans retired boats (both Boat#name_unique_in_club
  # and index_boats_on_club_id_and_lower_name do), but the picker and
  # Boats::NearMatch cover only active ones. So retiring "Majestic Red" and
  # then typing it again in "+ New boat…" fails the save with a bare "is
  # already a boat in this club" for a boat that is nowhere on screen — a dead
  # end mid-league-night. Name where the fix actually is instead.
  def retired_boat_named(name)
    key = name.to_s.strip.downcase
    return nil if key.blank?
    current_club.boats.where(active: false).detect { |boat| boat.name.downcase == key }
  end
end
