Recaptcha.configure do |config|
  Recaptcha.configuration.skip_verify_env.delete("test")

  config.site_key   = '6LfjUj4lAAAAAN0-WhxjiM_m-Q7V5RrOPpgwHc2c'
  config.secret_key = '6LfjUj4lAAAAAOGYCh-Hb3ibsw8hz8nD2esgOrJS'
end