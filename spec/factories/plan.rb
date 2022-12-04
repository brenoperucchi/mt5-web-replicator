FactoryBot.define do
  factory :plan do
    trait :plan1 do
      name { "Plan 1" }
      active_at { DateTime.now }
      amount {'50'} 
      amount_extra {'30'}     

      after(:create) do |plan, evaluator|
        %w(Trace Copy Slave).each do |item|
          if plan.plan_items.find_by(name: item).nil?
            plan.plan_items.create(name: item, amount:plan.amount_extra, active: "1", recurrent:true)
          end
        end
      end
    end
    trait :plan2 do
      name { "Plan 2" }
      active_at { DateTime.now }
      amount {'100'} 
      amount_extra {'30'}     

      after(:create) do |plan, evaluator|
        %w(Trace Copy Slave).each do |item|
          if plan.plan_items.find_by(name: item).nil?
            plan.plan_items.create(name: item, amount:plan.amount_extra, active: "1", recurrent:true)
          end
        end
      end
    end
  end



end