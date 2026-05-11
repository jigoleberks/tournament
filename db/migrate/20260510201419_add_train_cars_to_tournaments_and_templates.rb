class AddTrainCarsToTournamentsAndTemplates < ActiveRecord::Migration[8.0]
  def change
    add_column :tournaments,          :train_cars, :integer, array: true, default: [], null: false
    add_column :tournament_templates, :train_cars, :integer, array: true, default: [], null: false
  end
end
