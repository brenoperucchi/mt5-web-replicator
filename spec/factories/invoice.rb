FactoryBot.define do

  factory :invoice do
    name {"Trace#22-Account#101-2023-07"}
    state {"pending"}
    amount { 0.124004e4 }
    settings { {"payment_link"=>"https://checkout.stripe.com/c/pay/cs_test_factory"} }
    store_id { 1 }
    payment_id { 9 }
    plan_usage_id { 571 }
    response { {checkout_session_id: 'cs_test_factory'} }
  end
end
