class AddRecoveryToolEnabledToClubs < ActiveRecord::Migration[8.1]
  def change
    add_column :clubs, :recovery_tool_enabled, :boolean, default: false, null: false
  end
end
