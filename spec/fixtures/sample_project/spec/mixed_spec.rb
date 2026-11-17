# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Mixed results' do
  it 'fails with an expectation' do
    expect(1 + 1).to eq(3)
  end

  it 'is pending' do
    pending 'not done yet'
    raise 'boom'
  end

  it 'raises an error' do
    raise ArgumentError, 'bad argument'
  end

  context 'nested' do
    it 'passes' do
      expect(true).to be(true)
    end
  end
end
