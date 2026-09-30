require 'rails_helper'

# Devise's stock PasswordsController inherits the default "application" layout,
# which rendered a missing layouts/navbar partial (ActionView::MissingTemplate).
RSpec.describe 'Devise password reset page', type: :request do
  it 'renders the forgot-password form' do
    get new_user_password_path

    expect(response).to have_http_status 200
    expect(response.body).to include('Forgot your password?')
  end
end
