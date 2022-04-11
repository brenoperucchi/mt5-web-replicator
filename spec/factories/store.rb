FactoryBot.define do
  factory :store do
    name { "Store 1" }
    active_at { DateTime.now }
    tag_list { "" }
    volume_default {0.10} 
    plan {'plan1'} 
    plan_value {'30'} 
    plan_percent {'30'} 
    telegram_api_id { '980209'} 
    telegram_api_hash {'03062326232cb23c6770e7a735c2dae2'} 
    telegram_api_number {'5548984222627'} 
  end
end