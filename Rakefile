require_relative "config/application"

Rails.application.load_tasks

# Run the RSpec suite by default (rspec-rails registers the `spec` task).
if Rake::Task.task_defined?("spec")
  task default: :spec
end
