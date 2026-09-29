require 'rails_helper'
require Rails.root.join('db/migrate/20260929000000_drop_pay_tables')
require Rails.root.join('db/migrate/20260929120000_backfill_store_language')

RSpec.describe 'data migrations' do
  let(:connection) { ActiveRecord::Base.connection }

  describe DropPayTables do
    def drop_fixture_tables
      (DropPayTables::TABLES + DropPayTables::TABLES.map { |t| :"legacy_#{t}" }).each do |t|
        connection.drop_table(t, if_exists: true, force: :cascade)
      end
    end

    before { drop_fixture_tables }
    after { drop_fixture_tables }

    it 'keeps non-empty pay_* tables as legacy_pay_* and drops empty ones' do
      connection.create_table(:pay_customers) { |t| t.string :processor }
      connection.create_table(:pay_webhooks) { |t| t.string :event_type }
      connection.execute("INSERT INTO pay_customers (processor) VALUES ('stripe')")

      ActiveRecord::Migration.suppress_messages { DropPayTables.new.up }

      expect(connection.table_exists?(:legacy_pay_customers)).to be true
      expect(connection.select_value('SELECT COUNT(*) FROM legacy_pay_customers').to_i).to be == 1
      expect(connection.table_exists?(:pay_customers)).to be false
      expect(connection.table_exists?(:pay_webhooks)).to be false
      expect(connection.table_exists?(:legacy_pay_webhooks)).to be false
    end
  end

  describe BackfillStoreLanguage do
    it 'sets pt-BR on stores without a language and keeps the others' do
      plan = create(:plan, :plan1)
      blank = Store.create!(name: 'Blank', email: 'blank@store.com', url: 'blank', plan: plan)
      english = Store.create!(name: 'En', email: 'en@store.com', url: 'en', plan: plan, language: 'en')
      blank.update_column(:settings, blank.settings.except(:language, 'language'))

      2.times { ActiveRecord::Migration.suppress_messages { BackfillStoreLanguage.new.up } }

      expect(blank.reload.language).to be == 'pt-BR'
      expect(english.reload.language).to be == 'en'
    end
  end
end
