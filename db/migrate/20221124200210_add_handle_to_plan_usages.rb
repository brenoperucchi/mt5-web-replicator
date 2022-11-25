class AddHandleToPlanUsages < ActiveRecord::Migration[6.1]
  def change
    add_column :plan_usages, :handle, :string
  end
end
