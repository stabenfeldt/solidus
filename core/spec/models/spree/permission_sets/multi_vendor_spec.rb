require 'spec_helper'

describe Spree::PermissionSets::MultiVendor do
  let(:ability) { Spree::Ability.new(user) }

  subject { ability }

  # Inactive stock locations will default to not being visible
  # for users without explicit permissions.
  let!(:source_location) { create :stock_location, active: false }


  context "when activated" do
    before do
      user.stock_locations = stock_locations
      described_class.new(ability).activate!
    end

    context "when the user is associated with the stock location" do
      it { is_expected.to be_able_to(:display, Spree::StockItem) }
      it { is_expected.to be_able_to(:admin,   Spree::StockItem) }
      it { is_expected.to be_able_to(:create,  Spree::StockItem) }
      it { is_expected.to be_able_to(:manage,  Spree::StockItem) }
    end

    context "when the user is not associated with the stock location" do
      let(:stock_locations) {[]}

      it { is_expected.to_not be_able_to(:display, Spree::StockItem) }
      it { is_expected.to_not be_able_to(:admin,   Spree::StockItem) }
      it { is_expected.to_not be_able_to(:create,  Spree::StockItem) }
      it { is_expected.to_not be_able_to(:manage,  Spree::StockItem) }
    end
  end

end
