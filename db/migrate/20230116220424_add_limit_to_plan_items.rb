class AddLimitToPlanItems < ActiveRecord::Migration[6.1]
  def change
    add_column :plan_items, :limit, :integer, default:0 
  end
end
