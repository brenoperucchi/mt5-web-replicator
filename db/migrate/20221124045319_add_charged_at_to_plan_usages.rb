class AddChargedAtToPlanUsages < ActiveRecord::Migration[6.1]
  def change
    add_column :plan_usages, :charged_at, :datetime
  end
end
