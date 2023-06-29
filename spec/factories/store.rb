FactoryBot.define do
  factory :store do
    name { "Store 1" }
    active_at { DateTime.now }
    state { 1 }
    email { 'user@store1.com' }
    url { 'store1' }
    tag_list { "" }
    volume_default {0.10} 
    telegram_api_id { '980209'} 
    telegram_api_hash {'03062326232cb23c6770e7a735c2dae2'} 
    telegram_api_number {'5548984222627'} 

    after(:create) do |store, evaluator|
      store.customer_plans.create(name: :plan1, kind:0, amount:100)
    end

    trait :store2 do
      name { "Store 2" }
      active_at { DateTime.now }
      email { 'user@store2.com' }
      url { 'store2' }
      tag_list { "" }
      volume_default {0.10} 
      telegram_api_id { '980209'} 
      telegram_api_hash {'03062326232cb23c6770e7a735c2dae2'} 
      telegram_api_number {'5548984222627'} 

      after(:create) do |store, evaluator|
        store.customer_plans.create(name: :plan1, kind:0, amount:100)
      end
    end
  end
end