# frozen_string_literal: true

module Ballotage
  # Creates a ballot from form-style params, for the management page, the
  # composer and Workflows alike: start_date / end_date (YYYY-MM-DD), optional
  # start_time / end_time (HH:MM, default 00:01 / 23:59), kind
  # (admission|proposal), rejection_threshold or rejection_percent,
  # approval_rule, quorum_percent, result_visibility, keep_counts and, for
  # admissions, subject_username (the candidate).
  #
  # Raises Discourse::InvalidParameters for malformed input (400) and
  # Ballot::InvalidState or ActiveRecord::RecordInvalid for valid input that
  # can't make a ballot (422). The rules can't be changed afterwards: there is
  # no update path, so nobody can tune them after seeing counts.
  class BallotCreator
    def self.create!(actor, params)
      new(actor, params).create!
    end

    def initialize(actor, params)
      @actor = actor
      @params = params.to_h.with_indifferent_access
    end

    def create!
      starts_at = parse_in_zone(@params[:start_date], @params[:start_time].presence || "00:01")
      ends_at = parse_in_zone(@params[:end_date], @params[:end_time].presence || "23:59")
      if ends_at <= Time.zone.now
        raise Ballot::InvalidState, I18n.t("ballotage.errors.ends_in_past")
      end

      kind = @params[:kind].presence || "admission"
      proposal = kind == "proposal"

      ballot =
        Ballot.create!(
          title: @params[:title].to_s,
          starts_at: starts_at,
          ends_at: ends_at,
          created_by_id: @actor.id,
          kind: kind,
          subject_user: subject_user,
          rejection_threshold: int_param(:rejection_threshold) || 1,
          rejection_percent: int_param(:rejection_percent),
          approval_rule: @params[:approval_rule].presence || "majority",
          quorum_percent: int_param(:quorum_percent),
          # Admissions announce only the outcome; proposals their counts too.
          result_visibility:
            @params[:result_visibility].presence || (proposal ? "counts" : "outcome"),
          keep_counts: @params.key?(:keep_counts) ? @params[:keep_counts].to_s == "true" : proposal,
        )
      ballot.log_staff_action(@actor, "ballotage_create")
      ballot.trigger_event("created")
      ballot
    end

    private

    # A configured zone wins; otherwise the creator's profile zone, which
    # Discourse detects from their browser.
    def zone
      @zone ||=
        ActiveSupport::TimeZone[
          SiteSetting.ballotage_timezone.presence || @actor.user_option&.timezone.to_s
        ] || Time.zone
    end

    def subject_user
      username = Array.wrap(@params[:subject_username]).first.to_s.strip
      return nil if username.blank?
      User.find_by_username(username) || raise(Discourse::InvalidParameters.new(:subject_username))
    end

    def int_param(key)
      value = @params[key]
      return nil if value.blank?
      Integer(value.to_s, exception: false) || raise(Discourse::InvalidParameters.new(key))
    end

    # Strict: an impossible date or time is a 400, never an exception (500) or
    # a silent rollover (zone.parse turns 2026-02-30 into 2 March).
    def parse_in_zone(date, time)
      y, m, d = date.to_s.match(/\A(\d{4})-(\d{2})-(\d{2})\z/)&.captures&.map(&:to_i)
      hh, mm = time.to_s.match(/\A(\d{2}):(\d{2})\z/)&.captures&.map(&:to_i)
      unless y && hh && Date.valid_date?(y, m, d) && hh < 24 && mm < 60
        raise Discourse::InvalidParameters.new(:date)
      end
      zone.local(y, m, d, hh, mm)
    end
  end
end
