Recaptcha.configure do |config|
  Recaptcha.configuration.skip_verify_env.delete("test")

  config.site_key   = ENV.fetch('RECAPTCHA_SITE_KEY', 'test-recaptcha-site-key')
  config.secret_key = ENV.fetch('RECAPTCHA_SECRET_KEY', 'test-recaptcha-secret-key')
end
