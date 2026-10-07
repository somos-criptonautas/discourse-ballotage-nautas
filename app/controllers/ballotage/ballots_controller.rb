# frozen_string_literal: true

module Ballotage
  class BallotsController < ::ApplicationController
    requires_plugin ::Ballotage::PLUGIN_NAME
    # show serves published results to anyone who can read the post, which may
    # include anonymous visitors of a public topic.
    requires_login except: [:show]

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
      ballots = visible ? Ballot.active.includes(:subject_user, post: :topic).to_a : []

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
    # doesn't even reveal the title to them — unless the ballot has ended and
    # publishes its result to readers of its post.
    def show
      ballot = Ballot.find(params[:id])
      unless guardian.can_vote_in_ballotage? || guardian.can_oversee_ballotage? ||
               published_to_reader?(ballot)
        raise Discourse::NotFound
      end
      render json: { ballot: ballot_json(ballot) }
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
          .includes(:subject_user, post: :topic, participations: :user)
          .order(starts_at: :desc, id: :desc)
          .partition { |b| b.cancellable? }
          .flatten
      render json: {
               can_manage: guardian.can_manage_ballotage?,
               ballots: ballots.map { |b| ballot_json(b) },
             }
    end

    # POST /ballotage/ballots — see Ballotage::BallotCreator for the params.
    def create
      ballot = BallotCreator.create!(current_user, params.permit!.to_h)
      render json: { ballot: ballot_json(ballot) }, status: :created
    rescue Ballot::InvalidState => e
      render_json_error(e.message, status: 422)
    end

    # POST /ballotage/ballots/:id/cancel — scheduled or running ballots.
    def cancel
      ballot = Ballot.find(params[:id])
      begin
        ballot.cancel!
      rescue Ballot::InvalidState => e
        return render_json_error(e.message, status: 422)
      end
      ballot.log_staff_action(current_user, "ballotage_cancel")
      render json: { ballot: ballot_json(ballot) }
    end

    # POST /ballotage/ballots/:id/finalize — irreversibly deletes result and
    # participant list of an ended or cancelled ballot.
    def finalize
      ballot = Ballot.find(params[:id])
      begin
        ballot.finalize!
      rescue Ballot::InvalidState => e
        return render_json_error(e.message, status: 422)
      end
      ballot.log_staff_action(current_user, "ballotage_finalize")
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
      ballot.log_staff_action(current_user, "ballotage_delete")
      render json: success_json
    end

    private

    # One shape for every view: the post card, /ballotage and the management
    # list. Voters get their own has_voted; overseers additionally get
    # participation, and the counts once the ballot is over; everyone who may
    # read the post gets whatever result the ballot publishes.
    def ballot_json(ballot)
      # Freezes the outcome on the first view after the end, so the card never
      # waits for the next job run.
      ballot.close! if ballot.closed_at.nil? && ballot.state == "ended"
      oversees = guardian.can_oversee_ballotage?
      can_vote = guardian.can_vote_in_ballotage?

      json = {
        id: ballot.id,
        title: ballot.title,
        kind: ballot.kind,
        choices: ballot.choices,
        rejection_threshold: ballot.rejection_threshold,
        rejection_percent: ballot.rejection_percent,
        approval_rule: ballot.approval_rule,
        quorum_percent: ballot.quorum_percent,
        result_visibility: ballot.result_visibility,
        starts_at: ballot.starts_at,
        ends_at: ballot.ends_at,
        state: ballot.state,
        finalized: ballot.finalized?,
        can_vote: can_vote,
        has_voted: can_vote && ballot.voted?(current_user),
        post_url: (ballot.post.url if ballot.post && guardian.can_see?(ballot.post)),
        subject_user:
          (
            BasicUserSerializer.new(ballot.subject_user, root: false).as_json if ballot.subject_user
          ),
      }
      if ballot.outcome_visible_to?(guardian)
        json.merge!(
          outcome: ballot.outcome,
          closed_voter_count: ballot.closed_voter_count,
          closed_eligible_count: ballot.closed_eligible_count,
        )
      end
      if counts_visible?(ballot, oversees)
        json.merge!(
          black_count: ballot.black_count,
          white_count: ballot.white_count,
          abstain_count: ballot.abstain_count,
        )
      end
      return json unless oversees

      json.merge!(
        can_manage: guardian.can_manage_ballotage?,
        cancellable: ballot.cancellable?,
        finalizable: ballot.finalizable?,
        deletable: ballot.deletable?,
      )
      return json if ballot.finalized?

      # Participation is visible while the ballot runs; counts only once it has
      # ended. Showing both live would let someone match a new name on the list
      # to the counter that just moved. Cancelled ballots never show counts
      # (cancel zeroes them anyway).
      # Rows of deleted users are kept (see README), so count rows rather than
      # surviving users: voter_count always equals the sum of the counts.
      voters = ballot.participations.map(&:user).compact.sort_by { |u| u.username_lower }
      json[:voter_count] = ballot.participations.size
      json[:eligible_count] = eligible_count
      json[:voters] = voters.map { |u| { id: u.id, username: u.username, name: u.name } }
      json
    end

    # Counts after the end: overseers until finalizing; everyone else only
    # when the ballot publishes them. Never for a cancelled ballot — a manager
    # could cancel right after one vote.
    def counts_visible?(ballot, oversees)
      return true if ballot.counts_published?
      oversees && ballot.state == "ended" && !ballot.finalized?
    end

    def published_to_reader?(ballot)
      ballot.result_visibility != "overseers" && ballot.state == "ended" && ballot.post.present? &&
        guardian.can_see?(ballot.post)
    end

    def eligible_count
      return @eligible_count if defined?(@eligible_count)
      @eligible_count = Ballot.eligible_count
    end

    def ensure_can_oversee
      raise Discourse::InvalidAccess unless guardian.can_oversee_ballotage?
    end

    def ensure_can_manage
      raise Discourse::InvalidAccess unless guardian.can_manage_ballotage?
    end
  end
end
