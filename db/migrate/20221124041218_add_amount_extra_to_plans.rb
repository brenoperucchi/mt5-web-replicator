class AddAmountExtraToPlans < ActiveRecord::Migration[6.1]
  def change
    add_column :plans, :amount_extra, :decimal, precision: 10, scale: 2
  end
end
