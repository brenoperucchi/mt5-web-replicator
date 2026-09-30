require 'rails_helper'

# Telegram is an experimental feature behind ENABLE_TELEGRAM (off by default):
# nothing Telegram-related may run or be required when the flag is off.
RSpec.describe 'Telegram feature flag' do
  around do |example|
    original = Rails.configuration.x.telegram_enabled
    example.run
  ensure
    Rails.configuration.x.telegram_enabled = original
  end

  let(:plan) { create(:plan, :plan1) }

  it 'is disabled by default' do
    expect(Rails.configuration.x.telegram_enabled).to be false
    expect(BotTelegram.enabled?).to be false
  end

  it 'does not load the telegram-bot-ruby gem when the Telegram code is loaded' do
    [Transaction, TelegramJob, BotTelegram, Telegram::Util]
    expect($LOADED_FEATURES.grep(%r{/telegram/bot\.rb\z})).to be_empty
  end

  it 'keeps a Store valid without any telegram settings' do
    store = Store.new(name: 'No Telegram', email: 'nt@example.com', url: 'no-telegram', plan: plan)
    expect(store).to be_valid
  end

  it 'does not generate and persist a bot token on read when disabled' do
    store = create(:store, plan_id: plan.id)
    expect(store.telegram_bot_token).to be_nil
    expect(store.reload.settings[:telegram_bot_token]).to be_nil
  end

  it 'makes TelegramJob a no-op when disabled' do
    job = TelegramJob.new
    expect(job).not_to receive(:telegram_send_message)
    job.perform(123, 'hello')
  end

  describe 'GET /stores/telegram/python', type: :request do
    before { create(:store, plan_id: plan.id) }

    # (API::V1::APIStore isn't mounted; its copy of the endpoint is guarded too.)
    %w[v2 v3].each do |version|
      it "returns 404 on #{version} when disabled" do
        get "/api/#{version}/stores/telegram/python"
        expect(response).to have_http_status 404
      end
    end
  end
end
