FactoryBot.define do

  factory :invoice do
    name {"Trace#22-Account#101-2023-07"}
    state {"pending"}
    amount { 0.124004e4 }
    settings { {"payment_link"=>"https://www.mercadopago.com.br/checkout/v1/redirect?pref_id=00000000-00000000-0000-0000-0000-000000000000"} }
    store_id { 1 }
    payment_id { 9 }
    plan_usage_id { 571 }
    response {"{:status=>201,
        :response=>
            {'additional_info'=>',
             'auto_return'=>',
             'back_urls'=>{'failure'=>'https://signallocal.imentore.com.br:8443/mercadopago/webhook/1', 'pending'=>', 'success'=>'},
             'binary_mode'=>false,
             'client_id'=>'0000000000000000',
             'collector_id'=>0,
             'coupon_code'=>nil,
             'coupon_labels'=>nil,
             'date_created'=>'2023-07-12T17:42:24.777-04:00',
             'date_of_expiration'=>nil,
             'expiration_date_from'=>nil,
             'expiration_date_to'=>nil,
             'expires'=>false,
             'external_reference'=>'28',
             'id'=>'00000000-00000000-0000-0000-0000-000000000000',
             'init_point'=>'https://www.mercadopago.com.br/checkout/v1/redirect?pref_id=00000000-00000000-0000-0000-0000-000000000000',
             'internal_metadata'=>nil,
             'items'=>[{'id'=>'28', 'category_id'=>', 'currency_id'=>'BRL', 'description'=>', 'title'=>'Inscrição Plano Wizard', 'quantity'=>1, 'unit_price'=>1240.04}],
             'marketplace'=>'NONE',
             'marketplace_fee'=>0,
             'metadata'=>{},
             'notification_url'=>nil,
             'operation_type'=>'regular_payment',
             'payer'=>{'phone'=>{'area_code'=>', 'number'=>'}, 'address'=>{'zip_code'=>', 'street_name'=>', 'street_number'=>nil}, 'email'=>', 'identification'=>{'number'=>', 'type'=>'}, 'name'=>', 'surname'=>', 'date_created'=>nil, 'last_purchase'=>nil},
             'payment_methods'=>{'default_card_id'=>nil, 'default_payment_method_id'=>nil, 'excluded_payment_methods'=>[{'id'=>'}], 'excluded_payment_types'=>[{'id'=>'}], 'installments'=>nil, 'default_installments'=>nil},
             'processing_modes'=>nil,
             'product_id'=>nil,
             'redirect_urls'=>{'failure'=>', 'pending'=>', 'success'=>'},
             'sandbox_init_point'=>'https://sandbox.mercadopago.com.br/checkout/v1/redirect?pref_id=00000000-00000000-0000-0000-0000-000000000000',
             'site_id'=>'MLB',
             'shipments'=>{'default_shipping_method'=>nil, 'receiver_address'=>{'zip_code'=>', 'street_name'=>', 'street_number'=>nil, 'floor'=>', 'apartment'=>', 'city_name'=>nil, 'state_name'=>nil, 'country_name'=>nil}},
             'total_amount'=>nil,
             'last_updated'=>nil}
      }"}
  end
end
