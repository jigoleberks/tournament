class JudgeAction < ApplicationRecord
  belongs_to :judge_user, class_name: "User"
  belongs_to :catch

  enum :action, {
    approve:         0,
    flag:            1,
    disqualify:      2,
    manual_override: 3,
    dock_verify:     4
  }

  validates :action, presence: true
end
