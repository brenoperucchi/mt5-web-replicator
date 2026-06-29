class AddMessageIdToOrder < ActiveRecord::Migration[6.0]
  def change
    add_reference :orders, :message, index: true
  end
end
