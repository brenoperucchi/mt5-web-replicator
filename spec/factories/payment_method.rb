FactoryBot.define do
  factory :payment_method do
    trait :stripe do
      name { 'Stripe' }
      handle { 'stripe' }
    end
  end
end
