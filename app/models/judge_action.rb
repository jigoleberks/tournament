class JudgeAction < ApplicationRecord
  belongs_to :judge_user, class_name: "User"
  belongs_to :catch

  enum :action, {
    approve:             0,
    flag:                1,
    disqualify:          2,
    manual_override:     3,
    dock_verify:         4,
    add_reference_photo: 5,
    geofence_override:   6,
    correct_location:    7,
    reinstate:           8
  }

  validates :action, presence: true
end
