class BackfillStoreLanguage < ActiveRecord::Migration[7.2]
  # language lives in the serialized `settings` store. Stores without one used
  # to render Portuguese; the new default is English, so pin existing stores
  # to pt-BR to keep their current behavior.
  class MigrationStore < ActiveRecord::Base
    self.table_name = 'stores'
    store :settings, accessors: [:language]
  end

  def up
    MigrationStore.reset_column_information
    MigrationStore.find_each do |store|
      next if store.language.present?

      store.language = 'pt-BR'
      store.update_column(:settings, store.settings)
    end
  end

  def down
    # Data backfill: nothing to undo.
  end
end
