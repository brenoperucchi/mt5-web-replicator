class AddPlanIdToCustomer < ActiveRecord::Migration[6.1]
  def change
    add_reference :customers, :plan, foreign_key: true
  end
end
