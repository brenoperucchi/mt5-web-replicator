class CreatePayments < ActiveRecord::Migration[6.1]
  def change
    create_table :payments do |t|
      t.belongs_to :payment_method
      t.belongs_to :customer_plan
      t.belongs_to :store
      t.string :api_token, :webhook_token
      t.timestamps
    end
  end
end
