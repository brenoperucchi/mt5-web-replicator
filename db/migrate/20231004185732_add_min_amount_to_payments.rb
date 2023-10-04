class AddMinAmountToPayments < ActiveRecord::Migration[6.1]
  def change
    add_column :payments, :min_amount, :decimal
  end
end
