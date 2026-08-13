class AddPlacementsEvaluatedAtToCatches < ActiveRecord::Migration[8.1]
  def change
    add_column :catches, :placements_evaluated_at, :datetime
  end
end
