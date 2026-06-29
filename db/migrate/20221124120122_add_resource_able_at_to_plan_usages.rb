class AddResourceAbleAtToPlanUsages < ActiveRecord::Migration[6.1]
  def change
    add_reference :plan_usages, :resourceable, polymorphic: true 
  end
end
