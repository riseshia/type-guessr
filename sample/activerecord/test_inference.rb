# frozen_string_literal: true

# This file is NOT meant to be executed.
# It serves as a hover target for TypeGuessr type inference verification.
# Each line exercises a specific dynamic method pattern.

# rubocop:disable all

### Setup variables ###
user = User.new
post = Post.new
comment = Comment.new
tag = Tag.new
profile = Profile.new
tagging = Tagging.new

###############################################################################
# A. Column-based instance methods (per-column dynamic methods)
###############################################################################

# A-1. Readers (attribute getters)
user.name              # => String?
user.email             # => String?
user.age               # => Integer?
user.active            # => bool
user.score             # => Float?
user.balance           # => BigDecimal?
user.bio               # => String?
user.born_on           # => Date?
user.login_at          # => ActiveSupport::TimeWithZone?
user.password_digest   # => String?
user.role              # => String?
user.created_at        # => ActiveSupport::TimeWithZone?
user.updated_at        # => ActiveSupport::TimeWithZone?
user.id                # => Integer?

post.title             # => String?
post.body              # => String?
post.published         # => bool
post.published_at      # => ActiveSupport::TimeWithZone?
post.status            # => String?

comment.body           # => String?

profile.settings       # => Hash?

# A-2. Writers (attribute setters)
user.name = "Alice"
user.email = "alice@example.com"
user.age = 30
user.active = true
user.score = 9.5
user.balance = BigDecimal("100.50")
user.bio = "Hello"
user.born_on = Date.today
user.login_at = Time.now

# A-3. Predicates (attribute?)
user.name?             # => bool
user.email?            # => bool
user.age?              # => bool
user.active?           # => bool
user.bio?              # => bool

# A-4. Before type cast
user.name_before_type_cast
user.age_before_type_cast
user.active_before_type_cast

# A-5. Dirty tracking (per-column)
user.name_changed?              # => bool
user.name_was                   # => String?
user.name_change                # => [String?, String?]?
user.name_will_change!          # => void
user.name_previously_changed?   # => bool
user.name_previous_change       # => [String?, String?]?
user.name_in_database           # => String?
user.saved_change_to_name?      # => bool
user.saved_change_to_name       # => [String?, String?]?
user.will_save_change_to_name?  # => bool
user.name_before_last_save      # => String?

user.age_changed?               # => bool
user.age_was                    # => Integer?
user.age_change                 # => [Integer?, Integer?]?

###############################################################################
# B. Association instance methods
###############################################################################

# B-1. has_many
user.posts                      # => ActiveRecord::Associations::CollectionProxy[Post]
user.posts.build                # => Post
user.posts.create(title: "x")   # => Post
user.posts.create!(title: "x")  # => Post
user.posts.new                  # => Post
user.post_ids                   # => Array[Integer]
user.post_ids = [1, 2]

user.comments                   # => CollectionProxy[Comment]
user.comment_ids                # => Array[Integer]

# B-2. has_one
user.profile                    # => Profile?
user.build_profile              # => Profile
user.create_profile             # => Profile
user.create_profile!            # => Profile
user.reload_profile             # => Profile?

# B-3. belongs_to
post.user                       # => User?
post.user_id                    # => Integer?
post.build_user                 # => User
post.create_user                # => User
post.reload_user                # => User?

comment.commentable             # => (polymorphic)
comment.commentable_id          # => Integer?
comment.commentable_type        # => String?
comment.user                    # => User?

# B-4. has_many :through
post.tags                       # => CollectionProxy[Tag]
post.tag_ids                    # => Array[Integer]
post.taggings                   # => CollectionProxy[Tagging]

# B-5. has_and_belongs_to_many
tag.posts                       # => CollectionProxy[Post]
tag.post_ids                    # => Array[Integer]

# B-6. Association reload
user.reload_profile             # => Profile?
post.reload_user                # => User?

# B-7. Collection proxy query methods
user.posts.where(published: true)
user.posts.find(1)
user.posts.find_by(title: "x")
user.posts.first
user.posts.last
user.posts.count
user.posts.size
user.posts.length
user.posts.empty?
user.posts.any?
user.posts.exists?
user.posts.include?(post)
user.posts.order(:created_at)
user.posts.limit(10)
user.posts.offset(5)
user.posts.pluck(:title)
user.posts.sum(:status)
user.posts.minimum(:status)
user.posts.maximum(:status)
user.posts.average(:status)
user.posts.destroy_all
user.posts.delete_all
user.posts << post
user.posts.push(post)
user.posts.concat([post])
user.posts.delete(post)
user.posts.clear
user.posts.reload

###############################################################################
# C. Enum methods
###############################################################################

# C-1. Instance predicates
user.member?                    # => bool
user.admin?                     # => bool
user.moderator?                 # => bool

# C-2. Instance bang methods (transition)
user.member!                    # => void
user.admin!                     # => void
user.moderator!                 # => void

# C-3. Class-level scopes
User.member                     # => ActiveRecord::Relation[User]
User.admin                      # => ActiveRecord::Relation[User]
User.moderator                  # => ActiveRecord::Relation[User]
User.not_member                 # => ActiveRecord::Relation[User]
User.not_admin                  # => ActiveRecord::Relation[User]

# C-4. Post enum
post.draft?                     # => bool
post.published?                 # => bool
post.archived?                  # => bool
post.draft!
post.published!
post.archived!
Post.draft                      # => ActiveRecord::Relation[Post]
Post.published                  # => ActiveRecord::Relation[Post] (or scope)
Post.archived                   # => ActiveRecord::Relation[Post]

###############################################################################
# D. Class-level query methods (ActiveRecord::Querying)
###############################################################################

# D-1. Finders
User.find(1)                    # => User
User.find(1, 2, 3)             # => Array[User]
User.find_by(name: "Alice")    # => User?
User.find_by!(name: "Alice")   # => User
User.first                      # => User?
User.first!                     # => User
User.last                       # => User?
User.last!                      # => User
User.second                     # => User?
User.third                      # => User?
User.forty_two                  # => User?
User.take                       # => User?
User.take!                      # => User
User.sole                       # => User
User.find_sole_by(name: "x")   # => User

# D-2. Collection queries (return Relation)
User.all                        # => ActiveRecord::Relation[User]
User.where(active: true)       # => ActiveRecord::Relation[User]
User.where.not(role: :admin)   # => ActiveRecord::Relation[User]
User.order(:name)              # => ActiveRecord::Relation[User]
User.order(name: :asc)         # => ActiveRecord::Relation[User]
User.limit(10)                 # => ActiveRecord::Relation[User]
User.offset(5)                 # => ActiveRecord::Relation[User]
User.select(:name, :email)     # => ActiveRecord::Relation[User]
User.distinct                   # => ActiveRecord::Relation[User]
User.group(:role)              # => ActiveRecord::Relation[User]
User.having("count(*) > 1")   # => ActiveRecord::Relation[User]
User.reorder(:name)            # => ActiveRecord::Relation[User]
User.reverse_order              # => ActiveRecord::Relation[User]
User.none                       # => ActiveRecord::Relation[User]
User.unscoped                   # => ActiveRecord::Relation[User]
User.reselect(:name)           # => ActiveRecord::Relation[User]
User.extending                  # => ActiveRecord::Relation[User]

# D-3. Joins / Includes (eager loading)
User.joins(:posts)             # => ActiveRecord::Relation[User]
User.left_joins(:posts)        # => ActiveRecord::Relation[User]
User.left_outer_joins(:posts)  # => ActiveRecord::Relation[User]
User.includes(:posts)          # => ActiveRecord::Relation[User]
User.eager_load(:posts)        # => ActiveRecord::Relation[User]
User.preload(:posts)           # => ActiveRecord::Relation[User]
User.references(:posts)        # => ActiveRecord::Relation[User]

# D-4. Aggregation
User.count                      # => Integer
User.count(:age)               # => Integer
User.sum(:age)                 # => Numeric
User.average(:age)             # => BigDecimal?
User.minimum(:age)             # => Integer?
User.maximum(:age)             # => Integer?
User.ids                        # => Array[Integer]
User.pluck(:name)              # => Array
User.pluck(:name, :email)      # => Array
User.pick(:name)               # => String?
User.pick(:name, :email)       # => Array?

# D-5. Existence checks
User.exists?                    # => bool
User.exists?(1)                # => bool
User.exists?(name: "Alice")   # => bool
User.any?                      # => bool
User.many?                     # => bool
User.none?                     # => bool (Enumerable#none?, not .none)
User.empty?                    # => bool

# D-6. Creation (class-level)
User.create(name: "Bob")      # => User
User.create!(name: "Bob")     # => User
User.new(name: "Bob")         # => User
User.find_or_create_by(name: "x")      # => User
User.find_or_create_by!(name: "x")     # => User
User.find_or_initialize_by(name: "x")  # => User
User.create_or_find_by(name: "x")      # => User
User.create_or_find_by!(name: "x")     # => User

# D-7. Batch operations (class-level)
User.update_all(active: false)         # => Integer
User.delete_all                         # => Integer
User.destroy_all                        # => Array[User]

# D-8. Batch iteration
User.find_each { |u| u }               # => nil
User.find_each(batch_size: 100)        # => Enumerator
User.find_in_batches { |batch| batch } # => nil
User.find_in_batches(batch_size: 100)  # => Enumerator
User.in_batches { |relation| relation } # => nil
User.in_batches(of: 100)              # => ActiveRecord::Batches::BatchEnumerator

# D-9. Calculation
User.calculate(:sum, :age)             # => Numeric
User.calculate(:count, :all)           # => Integer

# D-10. Scoped queries (from scope declarations)
User.active                             # => ActiveRecord::Relation[User]
User.adults                             # => ActiveRecord::Relation[User]
Post.published                          # => ActiveRecord::Relation[Post]
Post.recent                             # => ActiveRecord::Relation[Post]

# D-11. Chaining
User.where(active: true).order(:name).limit(10).offset(5)
User.active.adults.order(:name)
Post.published.recent.includes(:user)

###############################################################################
# E. Instance persistence methods
###############################################################################

# E-1. Save
user.save                       # => bool
user.save!                      # => bool
user.save(validate: false)     # => bool

# E-2. Update
user.update(name: "New")       # => bool
user.update!(name: "New")      # => bool
user.update_attribute(:name, "New")  # => bool
user.update_column(:name, "New")     # => bool
user.update_columns(name: "New")     # => bool

# E-3. Delete / Destroy
user.destroy                    # => User
user.destroy!                   # => User
user.delete                    # => User (frozen)

# E-4. Reload
user.reload                     # => User

# E-5. Toggle
user.toggle(:active)           # => User
user.toggle!(:active)          # => bool

# E-6. Touch
user.touch                     # => bool
user.touch(:login_at)          # => bool

# E-7. Increment / Decrement
user.increment(:age)           # => User
user.increment!(:age)          # => User
user.decrement(:age)           # => User
user.decrement!(:age)          # => User

# E-8. State checks
user.new_record?               # => bool
user.persisted?                # => bool
user.destroyed?                # => bool
user.changed?                  # => bool
user.previously_new_record?    # => bool
user.frozen?                   # => bool

###############################################################################
# F. Instance dirty tracking (document-level)
###############################################################################

user.changed?                   # => bool
user.changed                    # => Array[String]
user.changes                    # => Hash
user.previous_changes           # => Hash
user.changed_attributes         # => Hash
user.has_changes_to_save?       # => bool
user.changes_to_save            # => Hash
user.saved_changes?             # => bool
user.saved_changes              # => Hash
user.clear_changes_information  # => void

###############################################################################
# G. Other DSL-generated methods
###############################################################################

# G-1. delegate
post.author_name                # => String? (delegated from user.name)

# G-2. accepts_nested_attributes_for
post.comments_attributes = [{ body: "hi" }]

# G-3. store_accessor
profile.theme                   # => untyped
profile.theme = "dark"
profile.language                # => untyped
profile.language = "en"
profile.notifications_enabled   # => untyped
profile.notifications_enabled = true

# G-4. has_secure_password
user.authenticate("password")  # => User | false
user.password = "secret"
user.password_confirmation = "secret"

# G-5. delegated_type
comment.entryable               # => Message | Bulletin
comment.entryable_id            # => Integer?
comment.entryable_type          # => String?
comment.message?                # => bool
comment.bulletin?               # => bool
comment.message                 # => Message?
comment.bulletin                # => Bulletin?
Comment.messages                # => ActiveRecord::Relation[Comment]
Comment.bulletins               # => ActiveRecord::Relation[Comment]

###############################################################################
# H. Relation chaining (return types remain Relation)
###############################################################################

relation = User.where(active: true)
relation.where(role: :admin)    # => ActiveRecord::Relation[User]
relation.or(User.where(role: :moderator)) # => ActiveRecord::Relation[User]
relation.and(User.where(age: 30))         # => ActiveRecord::Relation[User]
relation.not(role: :admin)      # => ActiveRecord::Relation[User] (Rails 7+)
relation.invert_where           # => ActiveRecord::Relation[User]
relation.merge(User.active)     # => ActiveRecord::Relation[User]
relation.rewhere(active: false) # => ActiveRecord::Relation[User]
relation.readonly               # => ActiveRecord::Relation[User]
relation.lock                   # => ActiveRecord::Relation[User]
relation.lock("FOR UPDATE")    # => ActiveRecord::Relation[User]
relation.create_with(role: :member) # => ActiveRecord::Relation[User]

# Terminal methods on Relation
relation.to_a                   # => Array[User]
relation.to_ary                 # => Array[User]
relation.load                   # => ActiveRecord::Relation[User]
relation.reload                 # => ActiveRecord::Relation[User]
relation.size                   # => Integer
relation.length                 # => Integer
relation.count                  # => Integer
relation.empty?                 # => bool
relation.any?                   # => bool
relation.many?                  # => bool
relation.none?                  # => bool
relation.each { |u| u }        # => iteration
relation.map { |u| u.name }    # => Array
relation.find_each { |u| u }   # => nil
relation.first                  # => User?
relation.last                   # => User?
relation.second                 # => User?
relation.take                   # => User?

# rubocop:enable all
