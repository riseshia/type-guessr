# frozen_string_literal: true

# This file is NOT meant to be executed.
# It serves as a hover target for TypeGuessr type inference verification.
# Each line exercises a specific dynamic method pattern.

# rubocop:disable all

### Setup variables ###
article = Article.new
author = Author.new
review = Review.new
comment = Comment.new
metadata = Metadata.new
address = Address.new
category = Category.new

###############################################################################
# A. Field-based instance methods (per-field dynamic methods)
###############################################################################

# A-1. Readers (field getters)
article.title              # => String?
article.body               # => String?
article.view_count         # => Integer?
article.rating             # => Float?
article.published          # => Boolean?
article.published_at       # => Time?
article.tags_list          # => Array?
article.options            # => Hash?
article.created_at         # => Time?
article.updated_at         # => Time?

author.name                # => String?
author.email               # => String?
author.age                 # => Integer?
author.active              # => Boolean?

review.body                # => String?
review.rating              # => Integer?
review.approved            # => Boolean?

comment.body               # => String?
comment.author_name        # => String?

address.street             # => String?
address.city               # => String?
address.zip                # => String?

# A-2. Writers (field setters)
article.title = "Hello"
article.view_count = 42
article.rating = 4.5
article.published = true
article.published_at = Time.now
article.tags_list = ["ruby", "rails"]
article.options = { key: "value" }

# A-3. Predicates (field?)
article.title?             # => bool
article.published?         # => bool
article.view_count?        # => bool (true if non-zero/non-nil)
author.name?               # => bool
author.active?             # => bool

# A-4. Dirty tracking (per-field)
article.title_changed?             # => bool
article.title_was                  # => String?
article.title_change               # => [String?, String?]?
article.title_will_change!         # => void
article.title_previously_changed?  # => bool
article.title_previous_change      # => [String?, String?]?

author.name_changed?               # => bool
author.name_was                    # => String?
author.age_changed?                # => bool
author.age_was                     # => Integer?

# A-5. Read/Write attribute
article.read_attribute(:title)     # => untyped
article.write_attribute(:title, "x") # => untyped

###############################################################################
# B. Association instance methods
###############################################################################

# B-1. belongs_to (referenced)
article.author                     # => Author?
article.author = author
article.author_id                  # => BSON::ObjectId?
article.author_id = BSON::ObjectId.new
article.build_author               # => Author
article.create_author(name: "x")   # => Author

review.article                     # => Article?
review.article_id                  # => BSON::ObjectId?
review.build_article               # => Article
review.create_article              # => Article

# B-2. has_many (referenced)
author.articles                    # => Mongoid::Criteria[Article] / HasMany proxy
author.articles.build              # => Article
author.articles.create(title: "x") # => Article
author.articles.create!(title: "x") # => Article
author.articles.new                # => Article
author.article_ids                 # => Array[BSON::ObjectId]
author.article_ids = []

article.reviews                    # => Mongoid::Criteria[Review] / HasMany proxy
article.review_ids                 # => Array[BSON::ObjectId]

# B-3. embeds_many
article.comments                   # => EmbedsMany proxy
article.comments.build(body: "x") # => Comment
article.comments.create(body: "x") # => Comment
article.comments.create!(body: "x") # => Comment
article.comments.new               # => Comment
article.comments << comment
article.comments.push(comment)
article.comments.concat([comment])
article.comments.delete(comment)
article.comments.delete_all
article.comments.destroy_all
article.comments.clear
article.comments.pop
article.comments.shift
article.comments.unshift(comment)
article.comments.length            # => Integer
article.comments.size              # => Integer
article.comments.count             # => Integer
article.comments.empty?            # => bool
article.comments.any?              # => bool
article.comments.first             # => Comment?
article.comments.last              # => Comment?
article.comments.each { |c| c }
article.comments.include?(comment) # => bool

# B-4. embeds_one
article.metadata                   # => Metadata?
article.metadata = metadata
article.build_metadata             # => Metadata
article.create_metadata(key: "x") # => Metadata

author.address                     # => Address?
author.address = address
author.build_address               # => Address
author.create_address(street: "x") # => Address

# B-5. embedded_in
comment.article                    # => Article?
comment.article = article
metadata.article                   # => Article?
address.author                     # => Author?

# B-6. Embedded document parent/root
comment._parent                    # => Article
comment._root                     # => Article

# B-7. has_and_belongs_to_many
article.categories                 # => HABTM proxy
article.categories.build(name: "x") # => Category
article.categories.create(name: "x") # => Category
article.category_ids               # => Array[BSON::ObjectId]
article.category_ids = []
article.categories << category
article.categories.push(category)
article.categories.delete(category)
article.categories.clear
article.categories.length          # => Integer
article.categories.size            # => Integer

category.articles                  # => HABTM proxy
category.article_ids               # => Array[BSON::ObjectId]

# B-8. has_many proxy query methods
author.articles.where(published: true)
author.articles.find(BSON::ObjectId.new)
author.articles.first
author.articles.last
author.articles.count
author.articles.size
author.articles.length
author.articles.empty?
author.articles.any?
author.articles.exists?
author.articles.order_by(title: 1)
author.articles.limit(10)
author.articles.skip(5)
author.articles.pluck(:title)
author.articles.distinct(:title)
author.articles.sum(:view_count)
author.articles.min(:view_count)
author.articles.max(:view_count)
author.articles.avg(:view_count)
author.articles.destroy_all
author.articles.delete_all
author.articles.update_all(published: false)
author.articles.each { |a| a }
author.articles.reload

###############################################################################
# C. Scope methods
###############################################################################

Article.published                  # => Mongoid::Criteria[Article]
Article.popular                    # => Mongoid::Criteria[Article]
Article.recent                     # => Mongoid::Criteria[Article]

# Chaining scopes
Article.published.popular
Article.published.recent

# Unscoped
Article.unscoped                   # => Mongoid::Criteria[Article]

###############################################################################
# D. Class-level query methods (Mongoid::Criteria / Queryable)
###############################################################################

# D-1. Finders
Article.find(BSON::ObjectId.new)   # => Article
Article.find_by(title: "x")       # => Article?
Article.find_by!(title: "x")      # => Article
Article.first                      # => Article?
Article.last                       # => Article?
Article.all                        # => Mongoid::Criteria[Article]
Article.count                      # => Integer
Article.size                       # => Integer
Article.length                     # => Integer
Article.exists?                    # => bool
Article.any?                       # => bool
Article.empty?                     # => bool

# D-2. Collection queries (return Criteria)
Article.where(published: true)     # => Mongoid::Criteria[Article]
Article.order_by(title: 1)        # => Mongoid::Criteria[Article]
Article.order_by(title: -1)       # => Mongoid::Criteria[Article]
Article.limit(10)                  # => Mongoid::Criteria[Article]
Article.skip(5)                    # => Mongoid::Criteria[Article]
Article.offset(5)                  # => Mongoid::Criteria[Article]
Article.batch_size(100)            # => Mongoid::Criteria[Article]
Article.no_timeout                 # => Mongoid::Criteria[Article]

# D-3. Field projection
Article.pluck(:title)              # => Array
Article.pluck(:title, :body)       # => Array
Article.distinct(:title)           # => Array
Article.only(:title, :body)       # => Mongoid::Criteria[Article]
Article.without(:body)            # => Mongoid::Criteria[Article]

# D-4. Aggregation
Article.sum(:view_count)           # => Numeric
Article.min(:view_count)           # => Integer?
Article.max(:view_count)           # => Integer?
Article.avg(:view_count)           # => Float?

# D-5. Query conditions (chainable)
Article.where(published: true)
Article.gt(view_count: 100)
Article.gte(view_count: 100)
Article.lt(view_count: 10)
Article.lte(view_count: 10)
Article.ne(published: false)
Article.in(title: ["A", "B"])
Article.nin(title: ["C"])
Article.exists(title: true)
Article.elem_match(comments: { body: "x" })

# D-6. Creation (class-level)
Article.create(title: "New")       # => Article
Article.create!(title: "New")      # => Article
Article.new(title: "New")          # => Article
Article.build(title: "New")        # => Article
Article.find_or_create_by(title: "x")     # => Article
Article.find_or_create_by!(title: "x")    # => Article
Article.find_or_initialize_by(title: "x") # => Article
Article.first_or_create(title: "x")       # => Article
Article.first_or_create!(title: "x")      # => Article

# D-7. Batch operations (class-level)
Article.destroy_all                # => void
Article.delete_all                 # => Integer
Article.update_all(published: false) # => Integer

# D-8. Iteration
Article.each { |a| a }
Article.each_with_index { |a, i| a }
Article.map { |a| a.title }

# D-9. Criteria conversion
criteria = Article.where(published: true)
criteria.to_a                      # => Array[Article]
criteria.entries                   # => Array[Article]
criteria.to_enum                   # => Enumerator
criteria.count                     # => Integer
criteria.size                      # => Integer
criteria.length                    # => Integer
criteria.exists?                   # => bool
criteria.each { |a| a }
criteria.map { |a| a.title }

# D-10. Criteria modification
criteria.build(title: "x")        # => Article
criteria.create(title: "x")       # => Article
criteria.create!(title: "x")      # => Article
criteria.first_or_create           # => Article
criteria.find_or_create_by(title: "x") # => Article
criteria.find_or_initialize_by(title: "x") # => Article
criteria.delete_all                # => Integer
criteria.destroy_all               # => void
criteria.update_all(published: false) # => Integer

# D-11. Chaining
Article.where(published: true).order_by(title: 1).limit(10).skip(5)
Article.published.popular.order_by(created_at: -1)

###############################################################################
# E. Instance persistence methods
###############################################################################

# E-1. Save
article.save                       # => bool
article.save!                      # => bool
article.save(validate: false)     # => bool

# E-2. Update
article.update(title: "New")       # => bool
article.update!(title: "New")      # => bool
article.update_attributes(title: "New")  # => bool (deprecated)
article.update_attributes!(title: "New") # => bool (deprecated)

# E-3. Delete / Destroy
article.destroy                    # => Article
article.delete                    # => bool

# E-4. Reload
article.reload                     # => Article

# E-5. Upsert
article.upsert                    # => Article

# E-6. Touch
article.touch                     # => bool

# E-7. State checks
article.new_record?               # => bool
article.persisted?                # => bool
article.destroyed?                # => bool

###############################################################################
# F. Atomic operations (Mongoid-specific)
###############################################################################

article.inc(view_count: 1)        # => Article
article.set(title: "Updated")     # => Article
article.set(title: "x", body: "y") # => Article (multi-field)
article.unset(:body)              # => Article
article.unset(:body, :rating)     # => Article (multi-field)
article.push(tags_list: "ruby")   # => Article
article.push(tags_list: ["a", "b"]) # => Article (multi-value)
article.pull(tags_list: "ruby")   # => Article
article.pull_all(tags_list: ["a", "b"]) # => Article
article.add_to_set(tags_list: "ruby") # => Article
article.pop(tags_list: 1)         # => Article (remove last)
article.pop(tags_list: -1)        # => Article (remove first)
article.bit(view_count: { and: 0xFF }) # => Article
article.bit(view_count: { or: 0x01 })  # => Article
article.rename(title: :heading)   # => Article

# Atomically block
article.atomically do
  article.inc(view_count: 1)
  article.set(title: "Atomic Update")
end

###############################################################################
# G. Instance dirty tracking (document-level)
###############################################################################

article.changed?                   # => bool
article.changed                    # => Array[String]
article.changes                    # => Hash
article.previous_changes           # => Hash
article.changed_attributes         # => Hash
article.clear_changes_information  # => void

###############################################################################
# H. Embedded document specific methods
###############################################################################

# H-1. Parent access
comment._parent                    # => Article
comment._root                     # => Article
comment._root?                    # => bool (false, it's embedded)

metadata._parent                   # => Article
metadata._root                    # => Article

address._parent                    # => Author
address._root                    # => Author

# H-2. Embedded persistence (via parent)
# Embedded docs are saved when parent is saved
article.comments.build(body: "hi")
article.save  # saves article + embedded comments

###############################################################################
# I. Timestamps methods (Mongoid::Timestamps)
###############################################################################

article.created_at                 # => Time?
article.updated_at                 # => Time?
article.created_at = Time.now
article.updated_at = Time.now

author.created_at                  # => Time?
author.updated_at                  # => Time?

###############################################################################
# J. Validation methods
###############################################################################

article.valid?                     # => bool
article.invalid?                   # => bool
article.validate                   # => bool
article.errors                    # => ActiveModel::Errors
article.errors.full_messages      # => Array[String]

###############################################################################
# K. Attribute access
###############################################################################

article.attributes                 # => Hash
article.attribute_names            # => Array[String]
article.has_attribute?(:title)    # => bool

# rubocop:enable all
