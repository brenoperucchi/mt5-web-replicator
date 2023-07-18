class RemoveConstraintToPlanCustomer < ActiveRecord::Migration[6.1]
  def change
    remove_foreign_key :plan_customers, name: :fk_rails_e292784f26
    remove_foreign_key :plan_customers, name: :fk_rails_fd569cbed8
  end
end
