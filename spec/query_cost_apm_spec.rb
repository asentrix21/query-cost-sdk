# frozen_string_literal: true

RSpec.describe QueryCostApm do
  it "has a version number" do
    expect(QueryCostApm::VERSION).not_to be nil
  end

  it "loads Sanitizer and Fingerprinter" do
    expect(QueryCostApm::Sanitizer).not_to be nil
    expect(QueryCostApm::Fingerprinter).not_to be nil
  end
end

