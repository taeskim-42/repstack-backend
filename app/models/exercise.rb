# frozen_string_literal: true

# Exercise pool for dynamic routine generation
# Stores all available exercises with their attributes
class Exercise < ApplicationRecord
  # Validations
  validates :name, presence: true, uniqueness: true
  validates :english_name, presence: true, uniqueness: true
  validates :muscle_group, presence: true, inclusion: {
    in: %w[chest back legs shoulders arms core cardio]
  }
  validates :difficulty, inclusion: { in: 1..5 }
  validates :min_level, inclusion: { in: 1..8 }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :for_muscle, ->(muscle) { where(muscle_group: muscle) }
  scope :for_level, ->(level) { where("min_level <= ?", level) }
  scope :for_difficulty, ->(max_diff) { where("difficulty <= ?", max_diff) }
  scope :with_equipment, ->(equip) { where("equipment @> ARRAY[?]::varchar[]", equip) }
  scope :no_equipment, -> { where("equipment = ARRAY['none']::varchar[] OR equipment = '{}'") }
  scope :bpm_compatible, -> { where(bpm_compatible: true) }
  scope :tabata_compatible, -> { where(tabata_compatible: true) }
  scope :dropset_compatible, -> { where(dropset_compatible: true) }

  # Fitness factor scopes
  scope :for_strength, -> { where("fitness_factors @> ARRAY['strength']::varchar[]") }
  scope :for_endurance, -> { where("fitness_factors @> ARRAY['muscular_endurance']::varchar[]") }
  scope :for_power, -> { where("fitness_factors @> ARRAY['power']::varchar[]") }
  scope :for_cardio, -> { where("fitness_factors @> ARRAY['cardiovascular']::varchar[]") }

  # Find exercises matching fitness factor
  def self.for_fitness_factor(factor)
    where("fitness_factors @> ARRAY[?]::varchar[]", factor.to_s)
  end

  # Find exercises for a specific split day
  def self.for_split(split_type, day)
    case split_type.to_sym
    when :full_body
      active
    when :upper_lower
      day == :upper ? where(muscle_group: %w[chest back shoulders arms]) : where(muscle_group: %w[legs core])
    when :push_pull_legs
      case day
      when :push then where(muscle_group: %w[chest shoulders]).or(where(movement_pattern: "push"))
      when :pull then where(muscle_group: %w[back arms]).or(where(movement_pattern: "pull"))
      when :legs then where(muscle_group: %w[legs core])
      end
    when :five_day
      for_muscle(day.to_s)
    else
      active
    end
  end

  # Check if exercise is suitable for user level
  def suitable_for_level?(user_level)
    min_level <= user_level
  end

  # Get ROM options as symbols
  def available_roms
    rom_options.map(&:to_sym)
  end

  # Check if exercise supports a training method
  def supports_method?(method)
    case method.to_sym
    when :bpm then bpm_compatible
    when :tabata then tabata_compatible
    when :dropset then dropset_compatible
    when :superset then superset_compatible
    else true
    end
  end

  # Build exercise hash for routine generation
  def to_routine_format(options = {})
    {
      exercise_id: id,
      name: options[:display_name] || display_name || name,
      english_name: english_name,
      target: muscle_group,
      secondary_targets: secondary_muscles,
      difficulty: difficulty,
      equipment: equipment,
      form_tips: form_tips,
      rom_options: rom_options,
      video_references: video_references.presence
    }.compact
  end

  # Video references from RAG knowledge
  # Format: [{ video_id: "abc123", title: "...", timestamp_start: 0, url: "..." }, ...]
  def add_video_reference(video_id:, title:, url:, timestamp_start: nil, chunk_id: nil)
    ref = { video_id: video_id, title: title, url: url }
    ref[:timestamp_start] = timestamp_start if timestamp_start
    ref[:chunk_id] = chunk_id if chunk_id

    # Avoid duplicates
    unless video_references.any? { |r| r["video_id"] == video_id }
      self.video_references = video_references + [ref]
    end
  end

  def video_urls
    video_references.map { |r| r["url"] }.compact
  end
end
