FactoryBot.define do
  factory :trace do
    active_at { DateTime.now }

    trait :first do
      name { 'RoboSignal' }
      name_id { '-481414224' }
      take_profit_limit {2} 
      kind {'telegram'}
    end
    trait :second do
      name { 'Perucchi Inc' }
      name_id { '-340961920' }      
      take_profit_limit {2} 
      kind {'telegram'}
    end
    trait :copy do
      name { 'SignalCopy' }
      name_id { '20001' }
      take_profit_limit {2} 
      kind {'copy'}
    end
  end
end