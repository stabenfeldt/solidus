module Spree
  module PermissionSets
    # A user should only have access to items belonging to the stock locations he belongs to.
    # He should only see activity belonging to his items.
    # E.g. Stock managment and orders
    #
    # Users can be associated with stock locations via the admin user interface.
    #
    # @see Spree::PermissionSets::Base
    #
    # https://github.com/CanCanCommunity/cancancan/wiki/defining-abilities

    class MultiVendor < PermissionSets::Base
      def activate!
        puts "\n\n\n MULTI VENDOR \n\n\n"
        cannot :view, Spree::StockItem
        can :view, Spree::StockItem, :stock_location_id => user.stock_locations.first.id
      end

      private

      def user_location_ids
        @user_location_ids ||= user.stock_locations.pluck(:id)
      end

    end
  end
end
