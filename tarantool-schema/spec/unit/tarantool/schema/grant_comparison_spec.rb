# frozen_string_literal: true

RSpec.describe Tarantool::Schema::GrantComparison do
  let(:grants) do
    [Tarantool::Schema::GrantSpec.build(:app, %i[read write], on: :codes),
     Tarantool::Schema::GrantSpec.build(:reporting, :read, on: :codes)]
  end

  def compare(masks, missing: []) = described_class.new(grants, Tarantool::Schema::LiveGrants.new(masks:, missing:))

  it 'finds nothing when every privilege is granted, extra ones included' do
    comparison = compare({ 'app' => 7, 'reporting' => 1 })

    expect(comparison.mismatches).to eq([])
    expect(comparison.missing).to eq([])
  end

  it 'plans only the privileges still missing' do
    comparison = compare({ 'app' => 1 })

    expect(comparison.missing.map(&:to_h)).to eq([{ user: :app, privileges: %w[write], space: :codes },
                                                  { user: :reporting, privileges: %w[read], space: :codes }])
  end

  it 'reports a grantee that does not exist' do
    comparison = compare({}, missing: %w[reporting])

    expect(comparison.mismatches).to eq(['grant reporting: no such user or role'])
    expect(comparison.missing.map(&:user)).to eq([:app])
  end

  it 'plans everything for a space that does not exist yet' do
    comparison = compare({})

    expect(comparison.mismatches).to eq([])
    expect(comparison.missing).to eq(grants)
  end
end
