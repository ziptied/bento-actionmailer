# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in bento-actionmailer.gemspec
gemspec

gem "rake", "~> 13.0"

gem "minitest", "~> 5.0"

gem "rubocop", "~> 1.21"

# Allow testing against different Rails versions
rails_version = ENV.fetch("RAILS_VERSION", "8.0")
gem "rails", "~> #{rails_version}"
