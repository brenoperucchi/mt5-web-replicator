FactoryBot.define do
  factory :trace do
    active_at { DateTime.now }
    contract_volume_max { 2 }

    trait :first do
      name { 'RoboSignal' }
      name_id { '-481414224' }
      take_profit_limit {2} 
      kind {'telegram'}
      customer_plan_ids { 1 }
    end
    trait :second do
      name { 'Perucchi Inc' }
      name_id { '-340961920' }      
      take_profit_limit {2} 
      kind {'telegram'}
      customer_plan_ids { 1 }
    end
    trait :copy do
      name { 'SignalCopy' }
      name_id { '20001' }
      take_profit_limit {2} 
      kind {'copy'}
      customer_plan_ids { 1 }
    end
    trait :copy2 do
      name { 'SignalCopy2' }
      name_id { '20002' }
      take_profit_limit {2} 
      kind {'copy'}
      customer_plan_ids { 1 }
    end
  end
end