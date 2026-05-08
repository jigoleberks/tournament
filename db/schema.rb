# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_07_180000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "catch_placements", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "catch_id", null: false
    t.datetime "created_at", null: false
    t.integer "slot_index", null: false
    t.bigint "species_id", null: false
    t.bigint "tournament_entry_id", null: false
    t.bigint "tournament_id", null: false
    t.datetime "updated_at", null: false
    t.index ["catch_id", "tournament_entry_id", "species_id", "slot_index"], name: "idx_placements_uniq", unique: true
    t.index ["catch_id"], name: "index_catch_placements_on_catch_id"
    t.index ["species_id"], name: "index_catch_placements_on_species_id"
    t.index ["tournament_entry_id", "species_id", "slot_index"], name: "idx_active_placements_uniq_per_slot", unique: true, where: "(active = true)"
    t.index ["tournament_entry_id"], name: "index_catch_placements_on_tournament_entry_id"
    t.index ["tournament_id", "species_id", "slot_index", "active"], name: "idx_placements_leaderboard"
    t.index ["tournament_id"], name: "index_catch_placements_on_tournament_id"
  end

  create_table "catches", force: :cascade do |t|
    t.string "app_build"
    t.decimal "barometric_pressure_hpa", precision: 7, scale: 2
    t.datetime "captured_at_device", null: false
    t.datetime "captured_at_gps"
    t.string "client_uuid", null: false
    t.datetime "created_at", null: false
    t.text "flags", default: [], null: false, array: true
    t.decimal "gps_accuracy_m", precision: 7, scale: 1
    t.decimal "latitude", precision: 9, scale: 6
    t.decimal "length_inches", precision: 5, scale: 2, null: false
    t.bigint "logged_by_user_id"
    t.decimal "longitude", precision: 9, scale: 6
    t.string "moon_phase"
    t.decimal "moon_phase_fraction", precision: 5, scale: 4
    t.text "note"
    t.bigint "species_id", null: false
    t.integer "status", default: 1, null: false
    t.datetime "synced_at"
    t.decimal "temperature_c", precision: 5, scale: 2
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.decimal "wind_speed_kph", precision: 5, scale: 1
    t.index ["client_uuid"], name: "index_catches_on_client_uuid", unique: true
    t.index ["logged_by_user_id"], name: "index_catches_on_logged_by_user_id"
    t.index ["species_id"], name: "index_catches_on_species_id"
    t.index ["user_id"], name: "index_catches_on_user_id"
  end

  create_table "club_memberships", force: :cascade do |t|
    t.bigint "club_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deactivated_at"
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["club_id"], name: "index_club_memberships_on_club_id"
    t.index ["deactivated_at"], name: "index_club_memberships_on_deactivated_at"
    t.index ["user_id", "club_id"], name: "index_club_memberships_on_user_id_and_club_id", unique: true
    t.index ["user_id"], name: "index_club_memberships_on_user_id"
  end

  create_table "clubs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_clubs_on_name", unique: true
  end

  create_table "judge_actions", force: :cascade do |t|
    t.integer "action", null: false
    t.jsonb "after_state", default: {}
    t.jsonb "before_state", default: {}
    t.bigint "catch_id", null: false
    t.datetime "created_at", null: false
    t.bigint "judge_user_id", null: false
    t.text "note"
    t.datetime "updated_at", null: false
    t.index ["catch_id", "created_at"], name: "index_judge_actions_on_catch_id_and_created_at"
    t.index ["catch_id"], name: "index_judge_actions_on_catch_id"
    t.index ["judge_user_id"], name: "index_judge_actions_on_judge_user_id"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.string "auth", null: false
    t.datetime "created_at", null: false
    t.string "endpoint", null: false
    t.integer "muted_tournament_ids", default: [], array: true
    t.datetime "muted_until"
    t.string "p256dh", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "scoring_slots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "slot_count", null: false
    t.bigint "species_id", null: false
    t.bigint "tournament_id", null: false
    t.datetime "updated_at", null: false
    t.index ["species_id"], name: "index_scoring_slots_on_species_id"
    t.index ["tournament_id", "species_id"], name: "index_scoring_slots_on_tournament_id_and_species_id", unique: true
    t.index ["tournament_id"], name: "index_scoring_slots_on_tournament_id"
  end

  create_table "sign_in_tokens", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.bigint "club_id"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "kind", default: "link", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.bigint "user_id", null: false
    t.index ["club_id"], name: "index_sign_in_tokens_on_club_id"
    t.index ["token"], name: "index_sign_in_tokens_on_token", unique: true
    t.index ["user_id", "kind"], name: "index_sign_in_tokens_on_user_id_and_kind"
    t.index ["user_id"], name: "index_sign_in_tokens_on_user_id"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "species", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text)", name: "index_species_on_lower_name", unique: true
  end

  create_table "tournament_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.bigint "tournament_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tournament_id"], name: "index_tournament_entries_on_tournament_id"
  end

  create_table "tournament_entry_members", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "tournament_entry_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["tournament_entry_id", "user_id"], name: "idx_on_tournament_entry_id_user_id_e8ee5ecca6", unique: true
    t.index ["tournament_entry_id"], name: "index_tournament_entry_members_on_tournament_entry_id"
    t.index ["user_id"], name: "index_tournament_entry_members_on_user_id"
  end

  create_table "tournament_judges", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "tournament_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["tournament_id", "user_id"], name: "index_tournament_judges_on_tournament_id_and_user_id", unique: true
    t.index ["tournament_id"], name: "index_tournament_judges_on_tournament_id"
    t.index ["user_id"], name: "index_tournament_judges_on_user_id"
  end

  create_table "tournament_template_scoring_slots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "slot_count", default: 1, null: false
    t.bigint "species_id", null: false
    t.bigint "tournament_template_id", null: false
    t.datetime "updated_at", null: false
    t.index ["species_id"], name: "index_tournament_template_scoring_slots_on_species_id"
    t.index ["tournament_template_id"], name: "idx_on_tournament_template_id_3bc6d165a6"
  end

  create_table "tournament_templates", force: :cascade do |t|
    t.boolean "awards_season_points", default: false, null: false
    t.boolean "blind_leaderboard", default: false, null: false
    t.bigint "club_id", null: false
    t.datetime "created_at", null: false
    t.integer "default_duration_days"
    t.time "default_end_time"
    t.time "default_start_time"
    t.integer "default_weekday"
    t.integer "mode", default: 0, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["club_id"], name: "index_tournament_templates_on_club_id"
  end

  create_table "tournaments", force: :cascade do |t|
    t.boolean "awards_season_points", default: false, null: false
    t.boolean "blind_leaderboard", default: false, null: false
    t.bigint "club_id", null: false
    t.datetime "created_at", null: false
    t.datetime "ends_at"
    t.boolean "judged", default: false, null: false
    t.integer "kind", default: 0, null: false
    t.datetime "lifecycle_ended_announced_at"
    t.boolean "local", default: true, null: false
    t.integer "mode", default: 0, null: false
    t.string "name", null: false
    t.boolean "requires_release_video", default: false, null: false
    t.string "season_tag"
    t.datetime "starts_at", null: false
    t.integer "template_source_id"
    t.datetime "updated_at", null: false
    t.index ["club_id", "starts_at", "ends_at"], name: "index_tournaments_on_club_id_and_starts_at_and_ends_at"
    t.index ["club_id"], name: "index_tournaments_on_club_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "deactivated_at"
    t.string "email", null: false
    t.string "length_unit", default: "inches", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["deactivated_at"], name: "index_users_on_deactivated_at"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "catch_placements", "catches"
  add_foreign_key "catch_placements", "species"
  add_foreign_key "catch_placements", "tournament_entries"
  add_foreign_key "catch_placements", "tournaments"
  add_foreign_key "catches", "species"
  add_foreign_key "catches", "users"
  add_foreign_key "catches", "users", column: "logged_by_user_id"
  add_foreign_key "club_memberships", "clubs"
  add_foreign_key "club_memberships", "users"
  add_foreign_key "judge_actions", "catches"
  add_foreign_key "judge_actions", "users", column: "judge_user_id"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "scoring_slots", "species"
  add_foreign_key "scoring_slots", "tournaments"
  add_foreign_key "sign_in_tokens", "clubs"
  add_foreign_key "sign_in_tokens", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "tournament_entries", "tournaments"
  add_foreign_key "tournament_entry_members", "tournament_entries"
  add_foreign_key "tournament_entry_members", "users"
  add_foreign_key "tournament_judges", "tournaments"
  add_foreign_key "tournament_judges", "users"
  add_foreign_key "tournament_template_scoring_slots", "species"
  add_foreign_key "tournament_template_scoring_slots", "tournament_templates"
  add_foreign_key "tournament_templates", "clubs"
  add_foreign_key "tournaments", "clubs"
end
