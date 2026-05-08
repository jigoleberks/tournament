class UseLowercaseUniqueIndexOnSpeciesName < ActiveRecord::Migration[8.1]
  # Closes the race where the case-insensitive validation and the case-sensitive
  # btree unique index disagree (two requests with "Walleye" and "walleye" both
  # passing). Functional index keeps display case in the column while enforcing
  # uniqueness on the normalized form.
  def change
    remove_index :species, :name
    add_index :species, "LOWER(name)", unique: true, name: "index_species_on_lower_name"
  end
end
