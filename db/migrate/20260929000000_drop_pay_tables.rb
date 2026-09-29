class DropPayTables < ActiveRecord::Migration[7.0]
  # The pay gem was configured but never wired into invoicing. Empty pay_*
  # tables are dropped; any table that still holds rows is kept as
  # legacy_pay_* so no billing history is lost.
  TABLES = %i[pay_webhooks pay_charges pay_payment_methods pay_subscriptions pay_merchants pay_customers].freeze

  def up
    TABLES.each do |table|
      next unless table_exists?(table)

      if select_value("SELECT 1 FROM #{quote_table_name(table)} LIMIT 1")
        rename_table table, "legacy_#{table}"
      else
        drop_table table, force: :cascade
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
