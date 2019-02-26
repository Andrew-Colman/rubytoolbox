# frozen_string_literal: true

#
# This class represents historical rubygem download data for a given date and gem.
#
# We only store weekly stats, on sundays, to make calculations between timeframes
# more consistent and easy to reason about, as well as saving on database storage
# massively. For the Ruby Toolbox's purposes, weekly stats are just fine(tm).
#
# The weekly persistence of stats happens via the `RubygemDownloadsPersistenceJob`,
# which takes a snapshot of whatever current downloads are stored on the `rubygems`
# table (if gem data updating is broken this might be outdated, but again on the
# average week the assumption is that this is good enough for our purposes).
#
# A number of additional stats is calculated using postgres trigger functions, based
# on the presence of previous data:
#
# `absolute_change_(week|month|year)`:
#   The total number of downloads just in that timeframe (if previous record is there)
#
# `relative_change_(week|month|year)`:
#   The percentage of all-time total downloads the timeframe's absolute downloads constitute
#
# `growth_change_(week|month|year)`:
#   The difference between current relative change and the previous one in the timeframe
#
# The trigger functions are not "clever" in triggering related updates if a historical record
# changes (since the assumption is they won't change anyway, it's historical data after all).
# If you change historical numbers, be sure to trigger a re-calculation of all related stats by
# issuing `UPDATE rubygem_download_stats SET id = id (WHERE rubygem_name = 'foo')".
#
class RubygemDownloadStat < ApplicationRecord
  belongs_to :rubygem,
             primary_key: :name,
             foreign_key: :rubygem_name,
             inverse_of:  :download_stats

  has_one :project, through: :rubygem

  def self.monthly(base_date: RubygemDownloadStat.maximum(:date))
    where("(#{table_name}.date <= ?)", base_date)
      .where("(#{table_name}.date - ?) % 28 = 0", base_date)
  end

  def self.with_associations
    includes(:rubygem, :project)
      .joins(:rubygem, :project)
  end

  def self.trending
    where.not(relative_change_month: nil, growth_change_month: nil) # Stats need to be present xD
         .where("relative_change_month < ?", 1000) # "Too high" growth happens usually with very new gems
         .where("absolute_change_month > ?", 10_000) # Baseline minimum downloads to be considered "trending"
         .where("growth_change_month > ?", 0) # Month-over-month growth must be positive to be trending
         .where("rubygems.latest_release_on > ?", 6.months.ago) # Must have had a recent release
         .merge(Project.with_bugfix_forks(false))
         .order("growth_change_month DESC NULLS LAST")
  end
end
