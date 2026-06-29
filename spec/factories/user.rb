FactoryBot.define do
  factory :user do
    trait :admin do
      email { 'admin@store.com' }
      password { '123123' }
    end
    trait :customer do
      email { 'customer@store.com' }
      password { '123123' }
    end
  end
end