# frozen_string_literal: true

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

ActiveRecord::Schema[8.1].define(version: 20_260_314_054_730) do
  create_table "bulletins", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.boolean "pinned"
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "comments", force: :cascade do |t|
    t.text "body"
    t.integer "commentable_id", null: false
    t.string "commentable_type", null: false
    t.datetime "created_at", null: false
    t.integer "entryable_id"
    t.string "entryable_type"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index %w[commentable_type commentable_id], name: "index_comments_on_commentable"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "subject"
    t.datetime "updated_at", null: false
  end

  create_table "posts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.boolean "published"
    t.datetime "published_at"
    t.integer "status"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_posts_on_user_id"
  end

  create_table "posts_tags", id: false, force: :cascade do |t|
    t.integer "post_id", null: false
    t.integer "tag_id", null: false
  end

  create_table "profiles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "settings"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_profiles_on_user_id"
  end

  create_table "taggings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "post_id", null: false
    t.integer "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["post_id"], name: "index_taggings_on_post_id"
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active"
    t.integer "age"
    t.decimal "balance"
    t.text "bio"
    t.date "born_on"
    t.datetime "created_at", null: false
    t.string "email"
    t.datetime "login_at"
    t.string "name"
    t.string "password_digest"
    t.integer "role"
    t.float "score"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "comments", "users"
  add_foreign_key "posts", "users"
  add_foreign_key "profiles", "users"
  add_foreign_key "taggings", "posts"
  add_foreign_key "taggings", "tags"
end
