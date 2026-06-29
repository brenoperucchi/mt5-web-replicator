Pay.setup do |config|
  # For use in the receipt/refund/renewal mailers
  config.business_name = "Imentore Business Name"
  config.business_address = "Imentore Business Address"
  config.application_name = "My Imentore"
  config.support_email = "suporte@imentore.com.br"

  config.send_emails = true

  config.default_product_name = "default"
  config.default_plan_name = "default"

  config.automount_routes = true
  config.routes_path = "/pay" # Only when automount_routes is true
end