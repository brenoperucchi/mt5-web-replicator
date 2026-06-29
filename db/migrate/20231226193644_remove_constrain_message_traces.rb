class RemoveConstrainMessageTraces < ActiveRecord::Migration[6.1]
  def change
    remove_foreign_key :messages_traces, name: :fk_rails_a8b5aafac3
    remove_foreign_key :messages_traces, name: :fk_rails_86ebf256bf
  end
end
