class CreateMessagesOrdersJoinTable < ActiveRecord::Migration[6.1]
  def change
    create_join_table :messages, :orders
  end
end
