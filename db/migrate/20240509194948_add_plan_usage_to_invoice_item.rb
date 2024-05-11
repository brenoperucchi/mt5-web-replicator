class AddPlanUsageToInvoiceItem < ActiveRecord::Migration[6.1]
  def change
    add_reference :invoice_items, :plan_usage
  end
end
