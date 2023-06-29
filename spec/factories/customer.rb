FactoryBot.define do
  factory :customer do
    trait :admin do
      name { 'admin' }
      role { 'customer' }
      role_control { 'admin' }
      customer_plan_ids { 1 }
    end
    trait :customer do
      name { 'client' }
      role { 'customer' }
      role_control { 'user' }
      # customer_plan_ids { 1 }
    end
    trait :customer2 do
      name { 'client2' }
      role { 'customer' }
      role_control { 'user' }
      # customer_plan_ids { 1 }
    end
  end
end