FactoryBot.define do
  factory :customer do
    trait :admin do
      name { 'admin' }
      role { 'admin' }
    end
    trait :client do
      name { 'client' }
      role { 'customer' }
      role_control { 'admin' }
    end
  end
end