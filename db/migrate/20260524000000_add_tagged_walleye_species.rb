class AddTaggedWalleyeSpecies < ActiveRecord::Migration[8.1]
  # Throwaway model so this migration never depends on the real Species
  # class, whose validations or constants may change in future.
  class Species < ActiveRecord::Base
    self.table_name = "species"
  end

  NAME = "Tagged Walleye".freeze

  def up
    return if Species.where("lower(name) = ?", NAME.downcase).exists?
    Species.create!(name: NAME)
  end

  def down
    Species.where("lower(name) = ?", NAME.downcase).delete_all
  end
end
