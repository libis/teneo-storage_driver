# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new

task :default => :spec

require 'github_changelog_generator/task'
GitHubChangelogGenerator::RakeTask.new :changelog do |config|
    config.user = 'libis'
    config.project = 'teneo-storage_driver'
    config.unreleased = false
  end
  
  require_relative "lib/teneo/storage_driver/version"
  
  desc "release the gem"
  task :update_changelog do
    `rake changelog`
    `git commit -am 'Changelog update'`
    `git push`
  end
  
  desc "publish patch version"
  task :publish do
    `gem bump patch --push --tag --release`
    `rake update_changelog`
  end
  
  desc "publish minor version"
  task :publish_minor do
    `gem bump minor --push --tag --release`
    `rake update_changelog`
  end
  
  desc "publish minor version"
  task :publish_major do
    `gem bump major --push --tag --release`
    `rake update_changelog`
  end
  