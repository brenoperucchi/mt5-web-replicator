class ChangeContentIdAndMagicNumberToBigInt < ActiveRecord::Migration[6.1]
  def change
    change_column :orders, :content_id, :bigint
  end
end