FactoryBot.define do
  factory :transaction do
    trait :first do
      ticket { "363873673" }
      action { "EXECUTION" }
      kind { "0" }
      price_request { "80.39" }
      price_open { "80.38" }
      stop_loss { "81.39" }
      take_profit { "80.19" }
      lot { "0.03" }
      comment { "RoboSignal" }
      magic { "123456" }
      open_at { "2020.10.21 01:18:09" }
    end
    trait :second do
      ticket { "363873674" }
      action { "EXECUTION" }
      kind { "0" }
      price_request { "44.44" }
      price_open { "44.45" }
      stop_loss { "44.40" }
      take_profit { "44.99" }
      lot { "0.03" }
      comment { "RoboSignal" }
      magic { "123456" }
      open_at { "2020.10.21 01:18:09" }
    end
  end
end