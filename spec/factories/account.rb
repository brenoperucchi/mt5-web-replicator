FactoryBot.define do
  factory :account do
    state { 'enable' }
    contract_volume { '1' }
    
    trait :slave1 do
      # name {5634787} 
      name {20100} 
      kind {'slave'} 
      meta_mode { 'demo' }
      meta_margin_mode { 'hedging' }
      trace_ids { 1 } 
    end

    trait :slave2 do
      # name {5634788} 
      name {20200} 
      kind {'slave'} 
      meta_mode { 'demo' }
      meta_margin_mode { 'hedging' }
      trace_ids { 1 } 
    end

    trait :slave3 do
      # name {5634789} 
      name {20300} 
      kind {'slave'} 
      meta_mode { 'demo' }
      meta_margin_mode { 'hedging' }
      trace_ids { 1 } 
    end

    trait :slave4 do
      name {20400} 
      kind {'slave'}  # 'slave' or 'copy'
      meta_mode { 'demo' }
      meta_margin_mode { 'hedging' }
      trace_ids { 2 } 
    end

    trait :slave_netting do
      name {30010}  
      kind {'slave'}  # 'slave' or 'copy'
      meta_mode { 'demo' }
      meta_margin_mode { 'netting' }
      # trace_ids { 2 } 
    end

    trait :copy do
      # name {5647753} 
      name {10100} 
      kind {'copy'} 
      meta_margin_mode { 'hedging' }
      trace_ids { 1 }
    end

    trait :copy2 do
      # name {201002}
      name {10200} 
      kind {'copy'} 
      meta_margin_mode { 'hedging' }
      trace_ids { 1 }
    end

    trait :copy_netting do   
      # name {201002}
      name {30100} 
      kind {'copy'} 
      meta_margin_mode { 'netting' }
    end
  end
end