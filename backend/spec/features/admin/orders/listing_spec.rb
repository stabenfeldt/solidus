require 'spec_helper'

describe "Orders Listing", type: :feature, js: true do
  stub_authorization!

  let!(:promotion) { create(:promotion_with_item_adjustment, code: "vnskseiw") }
  let(:promotion_code) { promotion.codes.first }

  before(:each) do
    allow_any_instance_of(Spree::OrderInventory).to receive(:add_to_shipment)
    @order1 = create(:order_with_line_items, created_at: 1.day.from_now, completed_at: 1.day.from_now, number: "R100")
    @order2 = create(:order, created_at: 1.day.ago, completed_at: 1.day.ago, number: "R200")
    visit spree.admin_orders_path
  end

  context "listing orders" do
    it "should list existing orders" do
      within_row(1) do
        expect(column_text(2)).to eq "R100"
        expect(column_text(3)).to eq "CART"
      end

      within_row(2) do
        expect(column_text(2)).to eq "R200"
      end
    end

    it "should be able to sort the orders listing" do
      # default is completed_at desc
      within_row(1) { expect(page).to have_content("R100") }
      within_row(2) { expect(page).to have_content("R200") }

      click_link "Completed At"

      # Completed at desc
      within_row(1) { expect(page).to have_content("R200") }
      within_row(2) { expect(page).to have_content("R100") }

      within('table#listing_orders thead') { click_link "Number" }

      # number asc
      within_row(1) { expect(page).to have_content("R100") }
      within_row(2) { expect(page).to have_content("R200") }
    end
  end

  context "searching orders" do
    it "should be able to search orders" do
      click_on 'Filter'
      fill_in "q_number_cont", with: "R200"
      click_on 'Filter Results'
      within_row(1) do
        expect(page).to have_content("R200")
      end

      # Ensure that the other order doesn't show up
      within("table#listing_orders") { expect(page).not_to have_content("R100") }
    end

    it "should be able to filter on variant_id" do
      click_on 'Filter'
      select2_search @order1.products.first.sku, from: Spree.t(:variant)
      click_on 'Filter Results'

      within_row(1) do
        expect(page).to have_content(@order1.number)
      end

      expect(page).not_to have_content(@order2.number)
    end

    context "when pagination is really short" do
      before do
        @old_per_page = Spree::Config[:orders_per_page]
        Spree::Config[:orders_per_page] = 1
      end

      after do
        Spree::Config[:orders_per_page] = @old_per_page
      end

      # Regression test for https://github.com/spree/spree/issues/4004
      it "should be able to go from page to page for incomplete orders" do
        10.times { Spree::Order.create email: "incomplete@example.com" }
        click_on 'Filter'
        uncheck "q_completed_at_not_null"
        click_on 'Filter Results'
        within(".pagination", match: :first) do
          click_link "2"
        end
        expect(page).to have_content("incomplete@example.com")
        click_on 'Filter'
        expect(find("#q_completed_at_not_null")).not_to be_checked
      end
    end

    it "should be able to search orders using only completed at input" do
      click_on 'Filter'
      fill_in "q_created_at_gt", with: Date.current

      # Just so the datepicker gets out of poltergeists way.
      page.execute_script("$('#q_created_at_gt').datepicker('widget').hide();")

      click_on 'Filter Results'
      within_row(1) { expect(page).to have_content("R100") }

      # Ensure that the other order doesn't show up
      within("table#listing_orders") { expect(page).not_to have_content("R200") }
    end

    context "filter on promotions" do
      before(:each) do
        @order1.order_promotions.build(
          promotion: promotion,
          promotion_code: promotion_code,
        )
        @order1.save
        visit spree.admin_orders_path
      end

      it "only shows the orders with the selected promotion" do
        click_on 'Filter'
        fill_in "q_promotions_codes_value_cont", with: promotion.codes.first.value
        click_on 'Filter Results'
        within_row(1) { expect(page).to have_content("R100") }
        within("table#listing_orders") { expect(page).not_to have_content("R200") }
      end
    end
  end
end
