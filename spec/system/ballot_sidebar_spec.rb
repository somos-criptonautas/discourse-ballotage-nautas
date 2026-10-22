# frozen_string_literal: true

RSpec.describe "Ballots in the sidebar" do
  fab!(:voting_group, :group)
  fab!(:voter) { Fabricate(:user, group_ids: [voting_group.id]) }
  fab!(:plain_user, :user)
  fab!(:admin)
  fab!(:ballot) do
    Ballotage::Ballot.create!(
      title: "Admission of Ana",
      starts_at: 1.hour.ago,
      ends_at: 1.day.from_now,
      created_by_id: admin.id,
    )
  end

  let(:link) { ".sidebar-section-link[data-link-name='ballotage']" }

  before do
    SiteSetting.ballotage_enabled = true
    SiteSetting.ballotage_voting_group = voting_group.id.to_s
    SiteSetting.navigation_menu = "sidebar"
  end

  it "shows no link by default" do
    sign_in(voter)
    visit("/latest")

    expect(page).to have_css(".sidebar-wrapper")
    expect(page).to have_no_css(link)
  end

  it "adds the link with a pending count to the Community section" do
    SiteSetting.ballotage_sidebar_section = "community"
    sign_in(voter)
    visit("/latest")

    expect(page).to have_css(
      ".sidebar-section[data-section-name='community'] #{link} .sidebar-section-link-content-badge",
      text: "1",
    )
  end

  it "puts the link in a section titled with the setting, without a count once voted" do
    SiteSetting.ballotage_sidebar_section = "Asamblea"
    ballot.cast_vote!(voter, "white")
    sign_in(voter)
    visit("/latest")

    expect(page).to have_css(".sidebar-section[data-section-name='ballotage']", text: /asamblea/i)
    expect(page).to have_css(link)
    expect(page).to have_no_css("#{link} .sidebar-section-link-content-badge")
  end

  it "hides the link from members who can neither vote nor oversee" do
    SiteSetting.ballotage_sidebar_section = "community"
    sign_in(plain_user)
    visit("/latest")

    expect(page).to have_css(".sidebar-wrapper")
    expect(page).to have_no_css(link)
  end
end
