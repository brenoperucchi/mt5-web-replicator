FactoryBot.define do
  factory :account do
    active_at { DateTime.now }

    trait :slave do
      name {5634787} 
      state {:enable} 
      kind {:slave} 
      trace_ids { 1 } 
    end
    trait :copy do
      name {5647753} 
      state {:enable} 
      kind {:slave} 
      trace_ids { 1 }
    end
  end
end