class AddResourceableToLogging < ActiveRecord::Migration[6.1]
  def change
    add_reference :loggings, :resourceable, polymorphic: true 
  end
end
