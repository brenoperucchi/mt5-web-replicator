class CreateMessagesTraces < ActiveRecord::Migration[6.1]
  def change
    create_table :messages_traces do |t|
      t.references :trace, null: false, foreign_key: true
      t.references :message, null: false, foreign_key: true
    end
  end
end
