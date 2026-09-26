# frozen_string_literal: true

RSpec.describe "Ballot embedded in a post" do
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

  before do
    SiteSetting.ballotage_enabled = true
    SiteSetting.ballotage_voting_group = voting_group.id.to_s
  end

  # Created after the plugin is enabled, so the tag is cooked into the embed.
  let!(:post) do
    Fabricate(:post, user: admin, raw: "Please vote.\n\n[ballotage id=#{ballot.id}]\n[/ballotage]")
  end

  it "lets a voter cast a secret vote from the post" do
    sign_in(voter)
    visit(post.url)

    find(".ballotage-card .ballotage-choice--white").click
    find(".dialog-footer .btn-primary").click

    expect(page).to have_css(".ballotage-card__done")
    expect(page).to have_no_css(".ballotage-choice")
    expect(ballot.reload.white_count).to eq(1)
  end

  it "shows only a neutral notice to members who cannot vote or oversee" do
    sign_in(plain_user)
    visit(post.url)

    expect(page).to have_css(".ballotage-embed__unavailable")
    expect(page).to have_no_content("Admission of Ana")
  end
end
