class AddPlanToPlanUsages < ActiveRecord::Migration[6.1]
  def change
    add_column :plan_usages, :plan_serializer, :text
  end
end
