class CreateMorphics < ActiveRecord::Migration[6.0]
  def change
    create_table :morphics do |t|
      t.belongs_to :account, index: true
      t.belongs_to :transaction, index: true
      # t.belongs_to :slave, index: true
      # t.belongs_to :trace, index: true
      # t.belongs_to :order, index: true
      # t.references :slaveable, polymorphic: true
      # t.references :transactionable, polymorphic: true
      t.timestamps
    end
  end
end
