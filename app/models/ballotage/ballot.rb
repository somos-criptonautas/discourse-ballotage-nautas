# frozen_string_literal: true

module Ballotage
  class Ballot < ActiveRecord::Base
    self.table_name = "ballotage_ballots"

    CHOICES = %w[black white].freeze

    class AlreadyVoted < StandardError
    end

    has_many :participations, class_name: "Ballotage::Participation", dependent: :delete_all
    belongs_to :post, optional: true

    validates :title, presence: true, length: { maximum: 255 }
    validates :starts_at, presence: true
    validates :ends_at, presence: true
    validate :ends_after_starts

    scope :not_cancelled, -> { where(cancelled_at: nil) }

    # Scheduled or running ballots, soonest first. Several may run at once.
    def self.active
      not_cancelled.where("ends_at > ?", Time.zone.now).order(:starts_at, :id)
    end

    # Open ballots the user can still vote in — drives the sidebar badge.
    def self.pending_for(user)
      active
        .where("starts_at <= ?", Time.zone.now)
        .where.not(id: Participation.where(user_id: user.id).select(:ballot_id))
    end

    # Links ballots embedded as [ballotage id=N] to the post, the first time
    # they are embedded and only when the author may manage ballots — so a
    # random member quoting the tag elsewhere doesn't move the link.
    def self.link_to_post(post)
      ids = post.cooked.to_s.scan(/data-ballot-id="(\d+)"/).flatten.map(&:to_i)
      return if ids.empty? || !Guardian.new(post.user).can_manage_ballotage?
      where(id: ids, post_id: nil).update_all(post_id: post.id)
    end

    # scheduled / open / ended / cancelled — derived from the clock, so nothing
    # has to flip a status at the start or end time.
    def state
      return "cancelled" if cancelled_at
      now = Time.zone.now
      return "scheduled" if now < starts_at
      return "open" if now < ends_at
      "ended"
    end

    def open?
      state == "open"
    end

    def over?
      %w[ended cancelled].include?(state)
    end

    def finalized?
      finalized_at.present?
    end

    def cancellable?
      %w[scheduled open].include?(state)
    end

    def finalizable?
      over? && !finalized?
    end

    def deletable?
      finalized?
    end

    def voted?(user)
      participations.exists?(user_id: user.id)
    end

    # Records participation and bumps one anonymous counter in the same
    # transaction. update_counters does not touch updated_at, so the ballot row
    # carries no timestamp of the last vote either.
    def cast_vote!(user, choice)
      raise Discourse::InvalidParameters.new(:choice) if CHOICES.exclude?(choice)

      transaction do
        # Row lock serialises votes against a concurrent cancel.
        lock!
        raise Discourse::InvalidAccess unless open?
        begin
          Participation.create!(ballot_id: id, user_id: user.id)
        rescue ActiveRecord::RecordNotUnique
          raise AlreadyVoted
        end
        self.class.update_counters(id, "#{choice}_count" => 1)
      end
    end

    # Irreversibly removes the result and the participant list; only the
    # title, period and whether it ran to the end or was cancelled remain.
    def finalize!
      transaction do
        participations.delete_all
        update_columns(black_count: 0, white_count: 0, finalized_at: Time.zone.now)
      end
    end

    private

    def ends_after_starts
      return if starts_at.blank? || ends_at.blank?
      errors.add(:ends_at, I18n.t("ballotage.errors.ends_before_starts")) if ends_at <= starts_at
    end
  end
end

# == Schema Information
#
# Table name: ballotage_ballots
#
#  id            :bigint           not null, primary key
#  post_id       :bigint
#  black_count   :integer          default(0), not null
#  cancelled_at  :datetime
#  ends_at       :datetime         not null
#  finalized_at  :datetime
#  starts_at     :datetime         not null
#  title         :string           not null
#  white_count   :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  created_by_id :bigint           not null
#
# Indexes
#
#  index_ballotage_ballots_on_ends_at  (ends_at)
#  index_ballotage_ballots_on_post_id  (post_id)
#
