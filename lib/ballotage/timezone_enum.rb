# frozen_string_literal: true

module Ballotage
  # Dropdown values for ballotage_timezone: every IANA zone, plus blank for
  # "automatic" (the creator's profile zone when creating, each viewer's own
  # zone when displaying).
  class TimezoneEnum < ::EnumSiteSetting
    def self.valid_value?(value)
      value.blank? || ActiveSupport::TimeZone[value].present?
    end

    def self.values
      @values ||=
        [{ name: I18n.t("ballotage.timezone_automatic"), value: "" }] +
          TZInfo::Timezone.all_identifiers.map { |zone| { name: zone, value: zone } }
    end

    def self.translate_names?
      false
    end
  end
end
