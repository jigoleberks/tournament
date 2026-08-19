module BoatsHelper
  # Options for a boat's captain <select>, always including the boat's CURRENT
  # captain even when they've since been deactivated and dropped out of the
  # club's member list.
  #
  # Without them the stored captain_user_id matches no option, nothing is
  # marked selected, and the browser preselects the first member alphabetically
  # — so an organizer who opens Boats to fix a typo in a name and hits Save
  # silently reassigns the boat to a stranger, with a green "Boat updated."
  # flash and Boats::RenameEntries cascading the change as if all was well.
  def boat_captain_options(club, boat)
    members = club.members.active.order(:name).to_a
    pairs = members.map { |member| [member.name, member.id] }
    if boat.captain && members.none? { |member| member.id == boat.captain_user_id }
      pairs.unshift(["#{boat.captain.name.strip} (inactive)", boat.captain_user_id])
    end
    options_for_select(pairs, boat.captain_user_id)
  end

  # Shared by both Boats screens so the twins can't drift on the one piece of
  # copy that has to be right. Deleting a boat unlinks its entries, which is
  # invisible on leaderboards — Leaderboards::Build ranks off the entry and its
  # own name column — but does cost the rename cascade and "same as last week",
  # so the count goes in front of the organizer at the moment of the click.
  def boat_delete_confirm(boat, entry_count)
    return "Delete #{boat.name}? This cannot be undone." if entry_count.to_i.zero?

    "Delete #{boat.name}? #{pluralize(entry_count, 'past entry')} will stay on the " \
      "leaderboards but lose the boat link, and \"same as last week\" will no longer " \
      "find its crews. This cannot be undone."
  end
end
