module Spree
  module Stock
    class Package
      attr_reader :stock_location, :contents
      attr_accessor :shipping_rates

      # @param stock_location [Spree::StockLocation] the stock location this package originates from
      # @param contents [Array<Spree::Stock::ContentItem>] the contents of this package
      def initialize(stock_location, contents=[])
        @stock_location = stock_location
        @contents = contents
        @shipping_rates = Array.new
      end

      # Adds an inventory unit to this package.
      #
      # @param inventory_unit [Spree::InventoryUnit] an inventory unit to be
      #   added to this package
      # @param state [:on_hand, :backordered] the state of the item to be
      #   added to this package
      def add(inventory_unit, state = :on_hand)
        contents << ContentItem.new(inventory_unit, state) unless find_item(inventory_unit)
      end

      # Adds multiple inventory units to this package.
      #
      # @param inventory_units [Array<Spree::InventoryUnit>] a collection of
      #   inventory units to be added to this package
      # @param state [:on_hand, :backordered] the state of the items to be
      #   added to this package
      def add_multiple(inventory_units, state = :on_hand)
        inventory_units.each { |inventory_unit| add(inventory_unit, state) }
      end

      # Removes a given inventory unit from this package.
      #
      # @param inventory_unit [Spree::InventoryUnit] the inventory unit to be
      #   removed from this package
      def remove(inventory_unit)
        item = find_item(inventory_unit)
        @contents -= [item] if item
      end

      # @return [Spree::Order] the order associated with this package
      def order
        # Fix regression that removed package.order.
        # Find it dynamically through an inventory_unit.
        contents.detect {|item| !!item.try(:inventory_unit).try(:order) }.try(:inventory_unit).try(:order)
      end

      # @return [Float] the summed weight of the contents of this package
      def weight
        contents.sum(&:weight)
      end

      # @return [Array<Spree::Stock::ContentItem>] the content items in this
      #   package which are on hand
      def on_hand
        contents.select(&:on_hand?)
      end

      # @return [Array<Spree::Stock::ContentItem>] the content items in this
      #   package which are backordered
      def backordered
        contents.select(&:backordered?)
      end

      # Find a content item in this package by inventory unit and optionally
      # state.
      #
      # @param inventory_unit [Spree::InventoryUnit] the desired inventory
      #   unit
      # @param state [:backordered, :on_hand, nil] the state of the desired
      #   content item, or nil for any state
      def find_item(inventory_unit, state = nil)
        contents.detect do |item|
          item.inventory_unit == inventory_unit &&
            (!state || item.state.to_s == state.to_s)
        end
      end

      # @param state [:backordered, :on_hand, nil] the state of the content
      #   items of which we want the quantity, or nil for the full quantity
      # @return [Fixnum] the number of inventory units in the package,
      #   counting only those in the given state if it was specified
      def quantity(state = nil)
        matched_contents = state.nil? ? contents : contents.select { |c| c.state.to_s == state.to_s }
        matched_contents.map(&:quantity).sum
      end

      # @return [Boolean] true if there are no inventory units in this
      #   package
      def empty?
        quantity == 0
      end

      # @return [String] the currency of the order this package belongs to
      def currency
        order.currency
      end

      # @return [Array<Spree::ShippingCategory>] the shipping categories of the
      #   variants in this package
      def shipping_categories
        contents.map { |item| item.variant.shipping_category }.compact.uniq
      end

      # @return [Array<Spree::ShippingMethod>] the shipping methods available
      #   for this pacakge based on the stock location that match all of the
      #   shipping categories + all shipping methods available to all
      #   that match the shipping categories
      def shipping_methods
        sl_methods = stock_location.shipping_methods.select { |sm| (sm.shipping_categories - shipping_categories).empty?}

        sc_methods = shipping_categories.map(&:shipping_methods).each { |cat| cat.select(&:available_to_all) }.reduce(:&).to_a

        # sms = (shipping_categories.map(&:shipping_methods).flatten.select(&:available_to_all) + stock_location.shipping_methods)
        # sms.select! { |sm| (shipping_categories - sm.shipping_categories).empty?}

        #sms.uniq.sort_by(&:id)
        (sl_methods + sc_methods).uniq.sort_by(&:id)
      end

      # @return [Spree::Shipment] a new shipment containing this package's
      #   inventory units, with the appropriate shipping rates and associated
      #   with the correct stock location
      def to_shipment
        # At this point we should only have one content item per inventory unit
        # across the entire set of inventory units to be shipped, which has
        # been taken care of by the Prioritizer
        contents.each { |content_item| content_item.inventory_unit.state = content_item.state.to_s }

        Spree::Shipment.new(
          stock_location: stock_location,
          shipping_rates: shipping_rates,
          inventory_units: contents.map(&:inventory_unit)
        )
      end
    end
  end
end
