class AddPlanUsageToPermissions < ActiveRecord::Migration[6.1]
  def change
    add_reference :permissions, :plan_usage
  end
end
