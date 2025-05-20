FactoryBot.define do
  factory :payment do
    min_amount {0}
  end
  trait :mercadopago do
    api_token { 'TEST-8003379344962428-070514-132303626f6b89ba73ab9f77b2a95c9d-77964627' }
    webhook_token { 'TEST-ea4aec5d-82ed-42c8-8c8a-abdd14b3690a' }
  end

end