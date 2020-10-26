FactoryBot.define do
  factory :trace do
    active_at { DateTime.now }
    lots { 0.05 }

    trait :first do
      name { 'RoboSignal' }
      name_id { '-481414224' }
      telegram_option { 'query_name' }
      telegram_image { true }
      take_profit { 'Agressive' }
    end
    trait :second do
      name { 'Perucchi Inc' }
      name_id { '-340961920' }
      telegram_option { 'query_name_id' }
      telegram_image { false }
      take_profit { 'Normal' }
    end
  end
end