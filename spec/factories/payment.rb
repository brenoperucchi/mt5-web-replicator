FactoryBot.define do
  factory :payment do
    min_amount {0}
  end
  trait :stripe do
    api_token { 'sk_test_x' }
    webhook_token { 'whsec_test' }
  end

end
