FactoryBot.define do
  factory :account do
    state { 'enable' }

    trait :slave1 do
      name {5634787} 
      kind {'slave'} 
      meta_mode { 'demo' }
      meta_margin_mode { 'hedging' }
      trace_ids { 1 } 
    end
    trait :slave2 do
      name {5634788} 
      kind {'slave'} 
      meta_mode { 'demo' }
      meta_margin_mode { 'hedging' }
      trace_ids { 1 } 
    end
    trait :copy do
      name {5647753} 
      kind {'copy'} 
      meta_margin_mode { 'hedging' }
      trace_ids { 1 }
    end
  end
end