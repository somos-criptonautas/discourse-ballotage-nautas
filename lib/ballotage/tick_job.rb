# frozen_string_literal: true

module ::Jobs
  # Opens, reminds and closes ballots on the clock. Each step stamps its own
  # *_at column, so a missed or doubled run neither skips nor repeats a notice.
  class BallotageTick < ::Jobs::Scheduled
    every 5.minutes

    def execute(_args)
      return unless SiteSetting.ballotage_enabled

      Ballotage::Ballot.due_for_open_notice.find_each(&:notify_opened!)
      Ballotage::Ballot.due_for_reminder.find_each(&:notify_reminder!)
      Ballotage::Ballot.due_for_close.find_each(&:close!)
    end
  end
end
