# frozen_string_literal: true

module Types
  class BodyInfoInputType < Types::BaseInputObject
    argument :height, Float, required: false
    argument :weight, Float, required: false
    argument :body_fat, Float, required: false
  end
end
