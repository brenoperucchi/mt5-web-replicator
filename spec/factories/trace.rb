FactoryBot.define do
  factory :trace do
    active_at { DateTime.current }
    contract_volume_max { 2 }
    
    # Associate customer_plan directly to ensure validation passes
    # after(:build) do |trace|
    #   # Only create if no permissions exist yet
    #   if trace.permissions.empty?
    #     # customer_plan = create(:customer_plan)
    #     trace.permissions << build(:permission, trace: trace, customer_plan: customer_plan)
    #   end
    # end
    
    # For use with store association
    # trait :with_store do
    #   transient do
    #     stores { [] }
    #   end
      
    #   after(:create) do |trace, evaluator|
    #     if evaluator.stores.present?
    #       evaluator.stores.each do |store|
    #         create(:store_trace, store: store, trace: trace)
    #       end
    #     end
    #   end
    # end

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
    trait :copy2 do
      name { 'SignalCopy2' }
      name_id { '20002' }
      take_profit_limit {2} 
      kind {'copy'}
    end

    trait :copy_netting do
      name { 'CopyNetting' }
      name_id { '30001' }
      take_profit_limit {2} 
      kind {'copy'}
    end
  end
end