FactoryBot.define do
  factory :account do
    state { :enable }

    trait :slave1 do
      name {5634787} 
      kind {:slave} 
      trace_ids { 1 } 
    end
    trait :slave2 do
      name {5634788} 
      kind {:slave} 
      trace_ids { 1 } 
    end
    trait :copy do
      name {5647753} 
      kind {:copy} 
      trace_ids { 1 }
    end
  end
end