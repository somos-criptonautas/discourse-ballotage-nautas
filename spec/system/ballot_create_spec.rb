# frozen_string_literal: true

RSpec.describe "Creating a ballot" do
  fab!(:admin)
  fab!(:candidate) { Fabricate(:user, username: "ana_garcia") }

  before { SiteSetting.ballotage_enabled = true }

  it "records the candidate of an admission and shows them on the card" do
    sign_in(admin)
    visit("/ballotage/manage")

    find(".d-page-header__actions .btn-primary").click
    find(".ballotage-create-modal input[name='title']").fill_in(with: "Admission of Ana")
    chooser = PageObjects::Components::SelectKit.new(".ballotage-create-modal .user-chooser")
    chooser.expand
    chooser.search(candidate.username)
    chooser.select_row_by_value(candidate.username)
    find(".ballotage-create-modal .form-kit__button[type='submit']").click

    expect(page).to have_no_css(".ballotage-create-modal")
    expect(page).to have_css(
      ".ballotage-card__candidate a[href='/u/#{candidate.username}']",
      text: "@#{candidate.username}",
    )
    expect(Ballotage::Ballot.last.subject_user).to eq(candidate)
  end

  it "doesn't offer a candidate for proposals" do
    sign_in(admin)
    visit("/ballotage/manage")

    find(".d-page-header__actions .btn-primary").click
    expect(page).to have_css(".ballotage-create-modal .user-chooser")

    find(".ballotage-create-modal input[value='proposal']").click

    expect(page).to have_no_css(".ballotage-create-modal .user-chooser")
  end
end
