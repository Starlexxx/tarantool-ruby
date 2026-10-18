# frozen_string_literal: true

RSpec.describe Tarantool::Schema::GrantSpec do
  it 'normalizes the grantee, privileges and space' do
    grant = described_class.build('app', :read, on: 'codes')

    expect(grant.to_h).to eq(user: :app, privileges: %w[read], space: :codes)
  end

  it 'rejects a grant without a grantee or a space' do
    expect { described_class.build(nil, :read, on: :codes) }.to raise_error(ArgumentError, 'grant without user')
    expect { described_class.build(:app, :read, on: nil) }.to raise_error(ArgumentError, 'grant app without space')
  end

  it 'lists what a live mask still lacks' do
    grant = described_class.build(:app, %i[read write], on: :codes)

    expect(grant.missing(1).privileges).to eq(%w[write])
    expect(grant.missing(0).privileges).to eq(%w[read write])
    expect(grant.missing(7)).to be_nil
  end
end
