FactoryBot.define do
  factory :order do
    state { 'executed' }
    content_id { 10000015 }
    active_at { DateTime.now }
    ready_at { DateTime.now }
    execute_at { DateTime.now }
    created_at { DateTime.now }
    updated_at { DateTime.now }
    symbol { 'AUDCAD' }
    deal_id { 10000015 }

    association :trace
    association :account
    association :store
  end
end
