module Spree
  class DefaultTaxZoneValidator < ActiveModel::Validator
    def validate(record)
      if record.included_in_price
        record.errors.add(:included_in_price, Spree.t(:included_price_validation)) unless Zone.default_tax
      end
    end
  end
end

module Spree
  class TaxRate < Spree::Base
    acts_as_paranoid

    # Need to deal with adjustments before calculator is destroyed.
    before_destroy :deals_with_adjustments_for_deleted_source

    include Spree::CalculatedAdjustments
    include Spree::AdjustmentSource

    belongs_to :zone, class_name: "Spree::Zone", inverse_of: :tax_rates
    belongs_to :tax_category, class_name: "Spree::TaxCategory", inverse_of: :tax_rates

    has_many :adjustments, as: :source

    validates :amount, presence: true, numericality: true
    validates :tax_category_id, presence: true
    validates_with DefaultTaxZoneValidator

    scope :by_zone, ->(zone) { where(zone_id: zone) }

    # Finds geographically matching tax rates for an order's tax zone.
    # We do not know if they are/aren't applicable until we attempt to apply these rates to
    # the items contained within the Order itself.
    # For instance, if a rate passes the criteria outlined in this method,
    # but then has a tax category that doesn't match against any of the line items
    # inside of the order, then that tax rate will not be applicable to anything.
    # For instance:
    #
    # Zones:
    #   - Spain (default tax zone)
    #   - France
    #
    # Tax rates: (note: amounts below do not actually reflect real VAT rates)
    #   21% inclusive - "Clothing" - Spain
    #   18% inclusive - "Clothing" - France
    #   10% inclusive - "Food" - Spain
    #   8% inclusive - "Food" - France
    #   5% inclusive - "Hotels" - Spain
    #   2% inclusive - "Hotels" - France
    #
    # Order has:
    #   Line Item #1 - Tax Category: Clothing
    #   Line Item #2 - Tax Category: Food
    #
    # Tax rates that should be selected:
    #
    #  21% inclusive - "Clothing" - Spain
    #  10% inclusive - "Food" - Spain
    #
    # If the order's address changes to one in France, then the tax will be recalculated:
    #
    #  18% inclusive - "Clothing" - France
    #  8% inclusive - "Food" - France
    #
    # Note here that the "Hotels" tax rates will not be used at all.
    # This is because there are no items which have the tax category of "Hotels".
    #
    # Under no circumstances should negative adjustments be applied for the Spanish tax rates.
    #
    # Those rates should never come into play at all and only the French rates should apply.
    def self.match(order_tax_zone)
      return [] unless order_tax_zone
      all_rates = includes(zone: { zone_members: :zoneable }).load

      rates_for_order_zone = all_rates.select { |rate| rate.zone.contains?(order_tax_zone) }
      rates_for_default_zone = all_rates.select { |rate| rate.default_vat? }

      # Imagine with me this scenario:
      # You are living in Spain and you have a store which ships to France.
      # Spain is therefore your default tax rate.
      # When you ship to Spain, you want the Spanish rate to apply.
      # When you ship to France, you want the French rate to apply.
      #
      # Normally, Spree would notice that you have two potentially applicable
      # tax rates for one particular item.
      # When you ship to Spain, only the Spanish one will apply.
      # When you ship to France, you'll see a Spanish refund AND a French tax.
      # This little bit of code at the end stops the Spanish refund from appearing.
      #
      # For further discussion, see https://github.com/spree/spree/issues/4397 and https://github.com/spree/spree/issues/4327.

      order_zone_tax_categories = rates_for_order_zone.map(&:tax_category)
      rates_for_default_zone.delete_if do |default_rate|
        order_zone_tax_categories.include?(default_rate.tax_category)
      end

      (rates_for_order_zone + rates_for_default_zone).uniq
    end

    # Pre-tax amounts must be stored so that we can calculate
    # correct rate amounts in the future. For example:
    # https://github.com/spree/spree/issues/4318#issuecomment-34723428
    def self.store_pre_tax_amount(item, rates)
      pre_tax_amount = case item
        when Spree::LineItem then item.discounted_amount
        when Spree::Shipment then item.discounted_cost
        end

      included_rates = rates.select(&:included_in_price)
      if included_rates.any?
        pre_tax_amount /= (1 + included_rates.map(&:amount).sum)
      end

      item.update_column(:pre_tax_amount, pre_tax_amount.round(2))
    end

    # This method is best described by the documentation on .match
    def self.adjust(order_tax_zone, items)
      rates = self.match(order_tax_zone)
      tax_categories = rates.map(&:tax_category)
      relevant_items, non_relevant_items = items.partition { |item| tax_categories.include?(item.tax_category) }
      unless relevant_items.empty?
        Spree::Adjustment.where(adjustable: relevant_items).tax.destroy_all # using destroy_all to ensure adjustment destroy callback fires.
      end
      relevant_items.each do |item|
        relevant_rates = rates.select { |rate| rate.tax_category == item.tax_category }
        store_pre_tax_amount(item, relevant_rates)
        relevant_rates.each do |rate|
          rate.adjust(order_tax_zone, item)
        end
      end
      non_relevant_items.each do |item|
        if item.adjustments.tax.present?
          item.adjustments.tax.destroy_all # using destroy_all to ensure adjustment destroy callback fires.
          item.update_columns pre_tax_amount: 0
        end
      end
    end

    # Creates necessary tax adjustments for the order.
    def adjust(order_tax_zone, item)
      amount = compute_amount(item)
      return if amount == 0

      included = included_in_price && default_zone_or_zone_match?(order_tax_zone)

      if amount < 0
        label = Spree.t(:refund) + ' ' + create_label
      end

      self.adjustments.create!({
        :adjustable => item,
        :amount => amount,
        :order_id => item.order_id,
        :label => label || create_label,
        :included => included
      })
    end

    # This method is used by Adjustment#update to recalculate the cost.
    def compute_amount(item)
      if included_in_price && !default_zone_or_zone_match?(item.order.tax_zone)
        # In this case, it's a refund.
        calculator.compute(item) * - 1
      else
        calculator.compute(item)
      end
    end

    def default_zone_or_zone_match?(order_tax_zone)
      Zone.default_tax.try!(:contains?, order_tax_zone) || self.zone.contains?(order_tax_zone)
    end

    def default_vat?
      included_in_price && zone.contains?(Spree::Zone.default_tax)
    end

    private

      def create_label
        label = ""
        label << (name.present? ? name : tax_category.name) + " "
        label << (show_rate_in_label? ? "#{amount * 100}%" : "")
        label << " (#{Spree.t(:included_in_price)})" if included_in_price?
        label
      end

  end
end
