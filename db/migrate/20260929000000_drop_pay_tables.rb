class DropPayTables < ActiveRecord::Migration[7.0]
  # The pay gem was configured but never wired into invoicing; its tables are unused.
  def up
    %i[pay_webhooks pay_charges pay_payment_methods pay_subscriptions pay_merchants pay_customers].each do |table|
      drop_table table, if_exists: true
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
