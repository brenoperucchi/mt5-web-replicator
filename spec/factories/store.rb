FactoryBot.define do
  factory :store do
    name { "Store 1" }
    active_at { DateTime.now }
  end
end