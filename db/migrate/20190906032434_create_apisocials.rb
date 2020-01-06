class CreateApisocials < ActiveRecord::Migration[6.0]
  def change
    create_table :apisocials do |t|

      t.timestamps
    end
  end
end
