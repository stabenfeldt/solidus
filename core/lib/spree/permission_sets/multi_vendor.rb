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
        cannot :view, Spree::StockItem
        if user_location_ids.include(Spree::StockItem.variant.stock_location_ids)
          can :view, Spree::StockItem
        end
      end

      private

      def user_location_ids
        @user_location_ids ||= user.stock_locations.pluck(:id)
      end

      def not_permitted_location_ids
        @not_permitted_location_ids ||= Spree::StockLocation.where.not(id: user_location_ids).pluck(:id)
      end
    end
  end
end
