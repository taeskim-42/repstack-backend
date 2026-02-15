# frozen_string_literal: true

class FeedbackChannel < ApplicationCable::Channel
  def subscribed
    stream_from "testflight_feedback"
  end
end
