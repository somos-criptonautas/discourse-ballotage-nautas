# frozen_string_literal: true

module Ballotage
  class BallotsController < ::ApplicationController
    requires_plugin ::Ballotage::PLUGIN_NAME
    requires_login

    skip_before_action :check_xhr, only: :page
    before_action :ensure_can_oversee, only: :index
    before_action :ensure_can_manage, only: %i[create cancel finalize destroy]

    # GET /ballotage, /ballotage/manage — serves the Ember app; the JSON
    # endpoints below do the permission checks.
    def page
      render "default/empty"
    end

    # GET /ballotage/current.json — scheduled and running ballots for the
    # /ballotage page. Empty for members who can neither vote nor oversee.
    def current
      visible = guardian.can_vote_in_ballotage? || guardian.can_oversee_ballotage?
      ballots = visible ? Ballot.active.includes(post: :topic).to_a : []

      render json: {
               can_vote: guardian.can_vote_in_ballotage?,
               can_oversee: guardian.can_oversee_ballotage?,
               # Served here rather than as a client setting so it isn't in the
               # site settings anonymous visitors can read.
               info_text: SiteSetting.ballotage_info_text.presence,
               ballots: ballots.map { |b| ballot_json(b) },
             }
    end

    # GET /ballotage/ballots/:id.json — one ballot, for the card embedded in a
    # post. 404 for members who can neither vote nor oversee, so the card
    # doesn't even reveal the title to them.
    def show
      unless guardian.can_vote_in_ballotage? || guardian.can_oversee_ballotage?
        raise Discourse::NotFound
      end
      render json: { ballot: ballot_json(Ballot.find(params[:id])) }
    end

    # POST /ballotage/vote — params: ballot_id, choice (black|white)
    def vote
      raise Discourse::InvalidAccess unless guardian.can_vote_in_ballotage?

      ballot = Ballot.find(params.expect(:ballot_id))
      return render_json_error(I18n.t("ballotage.errors.not_open"), status: 422) unless ballot.open?

      begin
        ballot.cast_vote!(current_user, params.expect(:choice).to_s)
      rescue Ballot::AlreadyVoted
        return render_json_error(I18n.t("ballotage.errors.already_voted"), status: 422)
      end

      # The response deliberately doesn't echo the choice back.
      render json: { ballot: ballot_json(ballot.reload) }
    end

    # GET /ballotage/ballots.json — management page.
    def index
      # Scheduled/open ballots first, then newest start first; id breaks ties so
      # ballots starting at the same time keep a stable order.
      ballots =
        Ballot
          .includes(post: :topic, participations: :user)
          .order(starts_at: :desc, id: :desc)
          .partition { |b| b.cancellable? }
          .flatten
      render json: {
               can_manage: guardian.can_manage_ballotage?,
               ballots: ballots.map { |b| ballot_json(b) },
             }
    end

    # POST /ballotage/ballots — params: title, start_date, end_date,
    # optional start_time / end_time (HH:MM, default 00:01 / 23:59)
    def create
      zone = ActiveSupport::TimeZone[SiteSetting.ballotage_timezone] || Time.zone
      starts_at = parse_in_zone(zone, params[:start_date], params[:start_time].presence || "00:01")
      ends_at = parse_in_zone(zone, params[:end_date], params[:end_time].presence || "23:59")

      if ends_at <= Time.zone.now
        return render_json_error(I18n.t("ballotage.errors.ends_in_past"), status: 422)
      end

      ballot =
        Ballot.create!(
          title: params.expect(:title),
          starts_at: starts_at,
          ends_at: ends_at,
          created_by_id: current_user.id,
        )

      render json: { ballot: ballot_json(ballot) }, status: :created
    end

    # POST /ballotage/ballots/:id/cancel — scheduled or running ballots.
    # Votes already cast are kept until the ballot is finalized.
    def cancel
      ballot = Ballot.find(params[:id])
      ballot.with_lock do
        unless ballot.cancellable?
          return render_json_error(I18n.t("ballotage.errors.not_cancellable"), status: 422)
        end
        ballot.update!(cancelled_at: Time.zone.now)
      end
      render json: { ballot: ballot_json(ballot) }
    end

    # POST /ballotage/ballots/:id/finalize — irreversibly deletes result and
    # participant list of an ended or cancelled ballot.
    def finalize
      ballot = Ballot.find(params[:id])
      unless ballot.finalizable?
        return render_json_error(I18n.t("ballotage.errors.not_finalizable"), status: 422)
      end
      ballot.finalize!
      render json: { ballot: ballot_json(ballot) }
    end

    # DELETE /ballotage/ballots/:id — removes a finalized ballot from the list
    # entirely. Only finalized ones: their result is already gone, so deleting
    # can never destroy a result in a single step.
    def destroy
      ballot = Ballot.find(params[:id])
      unless ballot.deletable?
        return render_json_error(I18n.t("ballotage.errors.not_deletable"), status: 422)
      end
      ballot.destroy!
      render json: success_json
    end

    private

    # One shape for every view: the post card, /ballotage and the management
    # list. Voters get their own has_voted; overseers additionally get
    # participation, and the black/white counts once the ballot is over.
    def ballot_json(ballot)
      json = {
        id: ballot.id,
        title: ballot.title,
        starts_at: ballot.starts_at,
        ends_at: ballot.ends_at,
        state: ballot.state,
        finalized: ballot.finalized?,
        can_vote: guardian.can_vote_in_ballotage?,
        has_voted: guardian.can_vote_in_ballotage? && ballot.voted?(current_user),
        post_url: (ballot.post.url if ballot.post && guardian.can_see?(ballot.post)),
      }
      return json unless guardian.can_oversee_ballotage?

      json.merge!(
        can_manage: guardian.can_manage_ballotage?,
        cancellable: ballot.cancellable?,
        finalizable: ballot.finalizable?,
        deletable: ballot.deletable?,
      )
      return json if ballot.finalized?

      # Participation is visible while the ballot runs; black/white only once it
      # is over. Showing both live would let someone match a new name on the
      # list to the counter that just moved.
      # Rows of deleted users are kept (see README), so count rows rather than
      # surviving users: voter_count always equals black_count + white_count.
      voters = ballot.participations.map(&:user).compact.sort_by { |u| u.username_lower }
      json[:voter_count] = ballot.participations.size
      json[:eligible_count] = eligible_count
      json[:voters] = voters.map { |u| { id: u.id, username: u.username, name: u.name } }
      if ballot.over?
        json[:black_count] = ballot.black_count
        json[:white_count] = ballot.white_count
      end
      json
    end

    def eligible_count
      return @eligible_count if defined?(@eligible_count)
      group_id = SiteSetting.ballotage_voting_group
      @eligible_count = group_id.blank? ? nil : GroupUser.where(group_id: group_id.to_i).count
    end

    def parse_in_zone(zone, date, time)
      y, m, d = date.to_s.match(/\A(\d{4})-(\d{2})-(\d{2})\z/)&.captures&.map(&:to_i)
      hh, mm = time.to_s.match(/\A(\d{2}):(\d{2})\z/)&.captures&.map(&:to_i)
      unless y && hh && Date.valid_date?(y, m, d) && hh < 24 && mm < 60
        raise Discourse::InvalidParameters.new(:date)
      end
      zone.local(y, m, d, hh, mm)
    end

    def ensure_can_oversee
      raise Discourse::InvalidAccess unless guardian.can_oversee_ballotage?
    end

    def ensure_can_manage
      raise Discourse::InvalidAccess unless guardian.can_manage_ballotage?
    end
  end
end
