class ChangeColumnTypeToBigInt < ActiveRecord::Migration[6.1]
  def change
    change_column :orders, :message_id, :bigint
  end
end