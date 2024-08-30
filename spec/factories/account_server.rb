FactoryBot.define do
  factory :account_server do
    name { 'broker_name' }
    created_at { Time.now }
    updated_at { Time.now }
  end
end