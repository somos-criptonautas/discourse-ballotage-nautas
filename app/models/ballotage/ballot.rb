# frozen_string_literal: true

module Ballotage
  class Ballot < ActiveRecord::Base
    self.table_name = "ballotage_ballots"

    # Admission: black/white balls. Proposal: white = approve, black = reject,
    # plus abstain. Reusing the two upstream counters keeps the secrecy model
    # (bare counters, no user reference) and upstream data unchanged.
    CHOICES = { "admission" => %w[black white], "proposal" => %w[white black abstain] }.freeze
    KINDS = CHOICES.keys.freeze
    APPROVAL_RULES = %w[majority two_thirds unanimous].freeze
    # Who sees the result once the ballot has ended: only overseers, everyone
    # who can read the post (outcome + turnout), or also the counts.
    VISIBILITIES = %w[overseers outcome counts].freeze
    REMINDER_BEFORE = 24.hours

    class AlreadyVoted < StandardError
    end

    has_many :participations, class_name: "Ballotage::Participation", dependent: :delete_all
    belongs_to :post, optional: true

    validates :title, presence: true, length: { maximum: 255 }
    validates :starts_at, presence: true
    validates :ends_at, presence: true
    validates :kind, inclusion: { in: KINDS }
    validates :approval_rule, inclusion: { in: APPROVAL_RULES }
    validates :result_visibility, inclusion: { in: VISIBILITIES }
    validates :rejection_threshold, numericality: { only_integer: true, greater_than: 0 }
    validates :quorum_percent,
              numericality: {
                only_integer: true,
                greater_than: 0,
                less_than_or_equal_to: 100,
              },
              allow_nil: true
    validate :ends_after_starts

    scope :not_cancelled, -> { where(cancelled_at: nil) }

    # Scheduled or running ballots, soonest first. Several may run at once.
    def self.active
      not_cancelled.where("ends_at > ?", Time.zone.now).order(:starts_at, :id)
    end

    # Links ballots embedded as [ballotage id=N] to the post, the first time
    # they are embedded and only when the author may manage ballots — so a
    # random member quoting the tag elsewhere doesn't move the link.
    def self.link_to_post(post)
      ids = post.cooked.to_s.scan(/data-ballot-id="(\d+)"/).flatten.map(&:to_i)
      return if ids.empty? || !Guardian.new(post.user).can_manage_ballotage?
      linked = where(id: ids, post_id: nil).update_all(post_id: post.id)
      return if linked.zero? || post.topic.nil?
      post.topic.upsert_custom_fields("ballotage" => true)
      tag_topic_title(post.topic, where(id: ids).order(:id).pick(:kind), post.user)
    end

    # Prefixes the topic title with the kind tag ("[ADMISSION] …"), in the
    # author's language, unless the title already carries it in any language.
    # Goes through PostRevisor so slug, search and live updates follow, without
    # adding an edit revision or bumping the topic.
    def self.tag_topic_title(topic, kind, author)
      key = "ballotage.kind_tag.#{kind}"
      known = I18n.available_locales.map { |locale| "[#{I18n.t(key, locale: locale)}]" }
      return if known.any? { |tag| topic.title.include?(tag) }

      tag = I18n.with_locale(author.effective_locale) { I18n.t(key) }
      title = "[#{tag}] #{topic.title}"
      return if title.length > SiteSetting.max_topic_title_length || topic.first_post.nil?

      PostRevisor.new(topic.first_post, topic).revise!(
        Discourse.system_user,
        { title: title },
        skip_validations: true,
        bypass_bump: true,
        skip_revision: true,
      )
    end

    def self.eligible_user_ids
      group_id = SiteSetting.ballotage_voting_group
      return [] if group_id.blank?
      GroupUser.where(group_id: group_id.to_i).pluck(:user_id)
    end

    def self.eligible_count
      group_id = SiteSetting.ballotage_voting_group
      group_id.blank? ? nil : GroupUser.where(group_id: group_id.to_i).count
    end

    # --- work for Jobs::BallotageTick ---

    def self.due_for_open_notice
      not_cancelled.where(opened_notified_at: nil).where(
        "starts_at <= :now AND ends_at > :now",
        now: Time.zone.now,
      )
    end

    # Only ballots running longer than the reminder window, so a short ballot
    # doesn't get "closing soon" right after "now open".
    def self.due_for_reminder
      now = Time.zone.now
      not_cancelled
        .where(reminded_at: nil)
        .where("starts_at <= ? AND ends_at > ?", now, now)
        .where("ends_at <= ?", now + REMINDER_BEFORE)
        .where("ends_at - starts_at > ?", "#{REMINDER_BEFORE.to_i} seconds")
    end

    def self.due_for_close
      not_cancelled.where(closed_at: nil).where("ends_at <= ?", Time.zone.now)
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

    def choices
      CHOICES.fetch(kind)
    end

    def voted?(user)
      participations.exists?(user_id: user.id)
    end

    # Records participation and bumps one anonymous counter in the same
    # transaction. update_counters does not touch updated_at, so the ballot row
    # carries no timestamp of the last vote either.
    def cast_vote!(user, choice)
      raise Discourse::InvalidParameters.new(:choice) if choices.exclude?(choice)

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

    # Freezes the outcome and turnout once an uncancelled ballot has ended, and
    # tells the voters. Idempotent: the job and the first page view after the
    # end may both call it.
    def close!
      return false if cancelled_at || Time.zone.now < ends_at

      closed =
        with_lock do
          next false if closed_at
          voters = participations.count
          eligible = self.class.eligible_count
          update_columns(
            outcome: decide(voters, eligible),
            closed_voter_count: voters,
            closed_eligible_count: eligible,
            closed_at: Time.zone.now,
          )
          true
        end
      notify(participations.pluck(:user_id), "closed") if closed
      closed
    end

    # Irreversibly removes the participant list and — unless this ballot
    # published its counts and chose to keep them — the counts. Title, period,
    # status and the frozen outcome remain.
    def finalize!
      close!
      transaction do
        participations.delete_all
        columns = { finalized_at: Time.zone.now }
        # Only an ended ballot that published its counts may keep them.
        unless keep_counts && result_visibility == "counts" && outcome.present?
          columns.merge!(black_count: 0, white_count: 0, abstain_count: 0)
        end
        update_columns(columns)
      end
    end

    def notify_opened!
      update_columns(opened_notified_at: Time.zone.now)
      notify(self.class.eligible_user_ids, "opened")
    end

    def notify_reminder!
      update_columns(reminded_at: Time.zone.now)
      voted = participations.pluck(:user_id)
      notify(self.class.eligible_user_ids - voted, "reminder")
    end

    # The outcome as the given viewer may see it: overseers always, everyone
    # else only when the ballot publishes it.
    def outcome_visible_to?(guardian)
      outcome.present? && (result_visibility != "overseers" || guardian.can_oversee_ballotage?)
    end

    private

    def decide(voters, eligible)
      return "no_quorum" if voters.zero?
      if quorum_percent && eligible.to_i > 0 && voters * 100 < quorum_percent * eligible
        return "no_quorum"
      end

      approved =
        if kind == "admission"
          black_count < rejection_threshold
        else
          yes = white_count
          no = black_count
          case approval_rule
          when "majority"
            yes > no
          when "two_thirds"
            yes > 0 && yes * 3 >= (yes + no) * 2
          when "unanimous"
            yes > 0 && no.zero?
          end
        end
      approved ? "approved" : "rejected"
    end

    def notify(user_ids, event)
      return if user_ids.empty?
      post = self.post
      User
        .where(id: user_ids)
        .find_each do |user|
          label, tagged_title =
            I18n.with_locale(user.effective_locale) do
              [
                I18n.t(
                  "ballotage.notifications.#{event}",
                  outcome: outcome_label_for(user),
                  count: (ends_at - Time.zone.now).fdiv(1.hour).ceil,
                ),
                "[#{I18n.t("ballotage.kind_tag.#{kind}")}] #{title}",
              ]
            end
          Notification.create!(
            notification_type: Notification.types[:custom],
            user_id: user.id,
            topic_id: post&.topic_id,
            post_number: post&.post_number,
            data: {
              message: "ballotage.notification",
              display_username: label,
              topic_title: tagged_title,
            }.to_json,
          )
        end
    end

    def outcome_label_for(user)
      return "" unless outcome_visible_to?(Guardian.new(user))
      ": " + I18n.t("ballotage.outcome.#{outcome}")
    end

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
#  id                    :bigint           not null, primary key
#  abstain_count         :integer          default(0), not null
#  approval_rule         :string           default("majority"), not null
#  black_count           :integer          default(0), not null
#  cancelled_at          :datetime
#  closed_at             :datetime
#  closed_eligible_count :integer
#  closed_voter_count    :integer
#  ends_at               :datetime         not null
#  finalized_at          :datetime
#  keep_counts           :boolean          default(FALSE), not null
#  kind                  :string           default("admission"), not null
#  opened_notified_at    :datetime
#  outcome               :string
#  quorum_percent        :integer
#  rejection_threshold   :integer          default(1), not null
#  reminded_at           :datetime
#  result_visibility     :string           default("overseers"), not null
#  starts_at             :datetime         not null
#  title                 :string           not null
#  white_count           :integer          default(0), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  created_by_id         :bigint           not null
#  post_id               :bigint
#
# Indexes
#
#  index_ballotage_ballots_on_ends_at  (ends_at)
#  index_ballotage_ballots_on_post_id  (post_id)
#
