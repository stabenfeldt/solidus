require 'spec_helper'

describe Spree::LineItem, :type => :model do
  let(:order) { create :order_with_line_items, line_items_count: 1 }
  let(:line_item) { order.line_items.first }

  context '#destroy' do
    it "fetches deleted products" do
      line_item.product.destroy
      expect(line_item.reload.product).to be_a Spree::Product
    end

    it "fetches deleted variants" do
      line_item.variant.destroy
      expect(line_item.reload.variant).to be_a Spree::Variant
    end

    it "returns inventory when a line item is destroyed" do
      expect_any_instance_of(Spree::OrderInventory).to receive(:verify)
      line_item.destroy
    end

    it "deletes inventory units" do
      expect { line_item.destroy }.to change { line_item.inventory_units.count }.from(1).to(0)
    end
  end

  context "#save" do
    context "line item changes" do
      before do
        line_item.quantity = line_item.quantity + 1
      end

      it "triggers adjustment total recalculation" do
        expect(line_item).to receive(:update_tax_charge) # Regression test for https://github.com/spree/spree/issues/4671
        expect(line_item).to receive(:recalculate_adjustments)
        line_item.save
      end
    end

    context "line item does not change" do
      it "does not trigger adjustment total recalculation" do
        expect(line_item).not_to receive(:recalculate_adjustments)
        line_item.save
      end
    end

    context "target_shipment is provided" do
      it "verifies inventory" do
        line_item.target_shipment = Spree::Shipment.new
        expect_any_instance_of(Spree::OrderInventory).to receive(:verify)
        line_item.save
      end
    end
  end

  context "#create" do
    let(:variant) { create(:variant) }

    before do
      create(:tax_rate, :zone => order.tax_zone, :tax_category => variant.tax_category)
    end

    context "when order has a tax zone" do
      before do
        expect(order.tax_zone).to be_present
      end

      it "creates a tax adjustment" do
        order.contents.add(variant)
        line_item = order.find_line_item_by_variant(variant)
        expect(line_item.adjustments.tax.count).to eq(1)
      end
    end

    context "when order does not have a tax zone" do
      before do
        order.bill_address = nil
        order.ship_address = nil
        order.save
        expect(order.reload.tax_zone).to be_nil
      end

      it "does not create a tax adjustment" do
        order.contents.add(variant)
        line_item = order.find_line_item_by_variant(variant)
        expect(line_item.adjustments.tax.count).to eq(0)
      end
    end
  end

  describe 'line item creation' do
    let(:variant) { create :variant }

    subject(:line_item) { Spree::LineItem.new(variant: variant, order: order) }

    # Tests for https://github.com/spree/spree/issues/3391
    context 'before validation' do
      before { line_item.valid? }

      it 'copies the variants price' do
        expect(line_item.price).to eq(variant.price)
      end

      it 'copies the variants cost_price' do
        expect(line_item.cost_price).to eq(variant.cost_price)
      end

      it 'copies the variants currency' do
        expect(line_item.currency).to eq(variant.currency)
      end

      # Test for https://github.com/spree/spree/issues/3481
      it 'copies the variants tax category' do
        expect(line_item.tax_category).to eq(line_item.variant.tax_category)
      end
    end

    # Specs for https://github.com/solidusio/solidus/pull/522#issuecomment-170668125
    context "with `#copy_price` defined" do
      before(:context) do
        Spree::LineItem.class_eval do
          def copy_price
            self.currency = "USD"
            self.cost_price = 10
            self.price = 20
          end
        end
      end

      after(:context) do
        Spree::LineItem.class_eval do
          remove_method :copy_price
        end
      end

      it 'should display a deprecation warning' do
        expect(ActiveSupport::Deprecation).to receive(:warn)
        Spree::LineItem.new(variant: variant, order: order)
      end

      it 'should run the user-defined copy_price method' do
        expect_any_instance_of(Spree::LineItem).to receive(:copy_price).and_call_original
        ActiveSupport::Deprecation.silence do
          Spree::LineItem.new(variant: variant, order: order)
        end
      end
    end
  end

  describe '.discounted_amount' do
    it "returns the amount minus any discounts" do
      line_item.price = 10
      line_item.quantity = 2
      line_item.promo_total = -5
      expect(line_item.discounted_amount).to eq(15)
    end
  end

  describe "#discounted_money" do
    it "should return a money object with the discounted amount" do
      expect(line_item.discounted_amount).to eq(10.00)
      expect(line_item.discounted_money.to_s).to eq "$10.00"
    end
  end

  describe '.currency' do
    it 'returns the globally configured currency' do
      line_item.currency == 'USD'
    end
  end

  describe ".money" do
    before do
      line_item.price = 3.50
      line_item.quantity = 2
    end

    it "returns a Spree::Money representing the total for this line item" do
      expect(line_item.money.to_s).to eq("$7.00")
    end
  end

  describe '.single_money' do
    before { line_item.price = 3.50 }
    it "returns a Spree::Money representing the price for one variant" do
      expect(line_item.single_money.to_s).to eq("$3.50")
    end
  end

  context "currency same as order.currency" do
    it "is a valid line item" do
      line_item = order.line_items.first
      line_item.currency = order.currency
      line_item.valid?

      expect(line_item.error_on(:currency).size).to eq(0)
    end
  end

  context "currency different than order.currency" do
    it "is not a valid line item" do
      line_item = order.line_items.first
      line_item.currency = "no currency"
      line_item.valid?

      expect(line_item.error_on(:currency).size).to eq(1)
    end
  end

  describe "#options=" do
    it "can handle updating a blank line item with no order" do
      line_item.options = { price: 123 }
    end

    it "updates the data provided in the options" do
      line_item.options = { price: 123 }
      expect(line_item.price).to eq 123
    end

    it "updates the price based on the options provided" do
      expect(line_item).to receive(:gift_wrap=).with(true)
      expect(line_item.variant).to receive(:gift_wrap_price_modifier_amount_in).with("USD", true).and_return 1.99
      line_item.options = { gift_wrap: true }
      expect(line_item.price).to eq 21.98
    end
  end

  describe "precision of pre_tax_amount" do
    let!(:line_item) { create :line_item, pre_tax_amount: 4.2051 }

    it "keeps four digits of precision even when reloading" do
      expect(line_item.reload.pre_tax_amount).to eq(4.2051)
    end
  end
end
