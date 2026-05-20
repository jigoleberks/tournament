class AddTroutAndBassSpecies < ActiveRecord::Migration[8.1]
  # Throwaway model so this migration never depends on the real Species
  # class, whose validations or constants may change in future.
  class Species < ActiveRecord::Base
    self.table_name = "species"
  end

  NEW_SPECIES = ["Stocked Trout", "Lake Trout", "Bass"].freeze

  def up
    NEW_SPECIES.each do |name|
      next if Species.where("lower(name) = ?", name.downcase).exists?
      Species.create!(name: name)
    end
  end

  def down
    NEW_SPECIES.each do |name|
      Species.where("lower(name) = ?", name.downcase).delete_all
    end
  end
end
