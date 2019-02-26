# frozen_string_literal: true

class TrendsController < ApplicationController
  def index
    latest_date = RubygemDownloadStat.maximum(:date)
    if latest_date
      redirect_to action: :show, id: latest_date
    else
      # This would normally only happen on a local, empty database
      render plain: "No stats data is available, please seed the database"
    end
  end

  def show
    @navigation = RubygemDownloadStat::Navigation.find(params[:id])

    @trends = RubygemDownloadStat
              .where(date: @navigation.date)
              .with_associations
              .trending
              .limit(48)
  end
end
