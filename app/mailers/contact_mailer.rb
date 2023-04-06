class ContactMailer < ApplicationMailer
  default from: 'contato@imentore.com.br'
  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.contact_mailer.email.subject
  #
  def email(user, password=nil)
    if Rails.env.production?
      delivery_options = { user_name: "contact@imentore.com",
                           password: "3e2w1q",
                           address: "imentore.com",
                           port: "587" }
     end


    @user = user
    @password = password
    # @message = message
    mail to: user.email, delivery_method_options: delivery_options, subject: "Seja Bem Vindo ao Imentore Copy"
  end
end
