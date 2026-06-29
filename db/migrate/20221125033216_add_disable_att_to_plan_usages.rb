class AddDisableAttToPlanUsages < ActiveRecord::Migration[6.1]
  def change
    add_column :plan_usages, :disable_at, :datetime
  end
end
