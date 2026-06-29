class AddTraceIdToPlanUsages < ActiveRecord::Migration[6.1]
  def change
    add_reference :plan_usages, :trace#, null: false, foreign_key: true
  end
end
