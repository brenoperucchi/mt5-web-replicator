class AddPlanUsageToInvoices < ActiveRecord::Migration[6.1]
  def change
    add_reference :invoices, :plan_usage
  end
end
