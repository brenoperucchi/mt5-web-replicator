FactoryBot.define do

  factory :store do
    name { "Store 1" }
    active_at { DateTime.current }
    state { 1 }
    email { 'user@store1.com' }
    url { 'store1' }
    tag_list { "" }
    volume_default {0.10} 
    telegram_api_id { '000000'}
    telegram_api_hash {'test_telegram_api_hash'}
    telegram_api_number {'5500000000000'}

    after(:create) do |store, evaluator|
      payment_method = store.payment_methods.create(name: 'Mercado Pago', handle: 'mercado_pago')
      payment_method.payments.first.update(api_token: 'TEST-0000000000000000-000000-0000000000000000000000000000-00000000', webhook_token: 'TEST-00000000-0000-0000-0000-000000000000')
      payment_method = store.payment_methods.create(name: 'Stripe',       handle: 'stripe')
      payment_method.payments.last.update(api_token: 'TEST-0000000000000000-000000-0000000000000000000000000000-00000000', webhook_token: 'TEST-00000000-0000-0000-0000-000000000000')
    end


    after(:create) do |store, evaluator|
      store.customer_plans.create(name: :plan1, kind:0, amount:100, payment: store.payments.first, due_at_dates: 5)
      store.update(payment_id: 1)
    end

    trait :store2 do
      name { "Store 2" }
      active_at { DateTime.current }
      email { 'user@store2.com' }
      url { 'store2' }
      tag_list { "" }
      volume_default {0.10} 
      telegram_api_id { '000000'}
      telegram_api_hash {'test_telegram_api_hash'}
      telegram_api_number {'5500000000000'}


      after(:create) do |store, evaluator|
        payment_method = store.payment_methods.create(name: 'Mercado Pago', handle: 'mercado_pago')
        payment_method.payments.first.update(api_token: 'TEST-0000000000000000-000000-0000000000000000000000000000-00000000', webhook_token: 'TEST-00000000-0000-0000-0000-000000000000')
        payment_method = store.payment_methods.create(name: 'Stripe',       handle: 'stripe')
        payment_method.payments.last.update(api_token: 'TEST-0000000000000000-000000-0000000000000000000000000000-00000000', webhook_token: 'TEST-00000000-0000-0000-0000-000000000000')
      end

      after(:create) do |store, evaluator|
        store.customer_plans.create(name: :plan1, kind:0, amount:100, amount_discount:30, payment: store.payments.first, due_at_dates: 5)
        store.update(payment_id: 1)
      end

    end
  end
end
