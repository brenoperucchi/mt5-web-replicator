require 'rails_helper'

# A fresh install has no traces; the marketing home page used to look up a
# hardcoded Trace id and returned 404.
RSpec.describe 'Home page', type: :request do
  it 'renders on an empty database' do
    get '/'

    expect(response).to have_http_status 200
  end
end
