FactoryBot.define do
  factory :payment do
    min_amount {0}
  end
  trait :mercadopago do
    api_token { 'TEST-0000000000000000-000000-0000000000000000000000000000-00000000' }
    webhook_token { 'TEST-00000000-0000-0000-0000-000000000000' }
  end

end
