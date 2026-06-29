class ChangeContentIdOrders < ActiveRecord::Migration[6.1]
  def change
    change_column :orders, :content_id, 'integer USING CAST(content_id AS BIGINT)'
  end
end
