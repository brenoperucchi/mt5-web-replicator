require 'rails_helper'

# Regression: API::V3::BasePresenter#parse_params used to `eval` the stored
# request params (Ruby Hash#inspect text), allowing remote code execution.
RSpec.describe API::V3::BasePresenter do
  let(:presenter) { described_class.new }

  around do |example|
    Dir.mktmpdir { |dir| @tmpdir = dir; example.run }
  end

  it 'never evaluates Ruby code embedded in legacy Hash#inspect params' do
    target = File.join(@tmpdir, 'pwned')
    malicious = %({"account_id"=>"1", "x"=>File.write(#{target.inspect}, "owned")})

    expect { presenter.parse_params(malicious) }.not_to raise_error
    expect(File.exist?(target)).to be(false)
  end

  it 'round-trips JSON params containing file inspect strings and code-looking values' do
    target = File.join(@tmpdir, 'pwned')
    original = { 'account_id' => '3000064180', 'data' => '#<File:/tmp/RackMultipart.txt>',
                 'cmd' => "system('touch #{target}')" }

    expect(presenter.parse_params(original.to_json)).to eq(original)
    expect(File.exist?(target)).to be(false)
  end
end
