require 'spec_helper'
require 'tasks/rake_config'

RSpec.describe 'ensure migrations are current', isolation: :truncation do
  before do
    allow(RakeConfig).to receive(:config).and_return(TestConfig.config_instance)
  end

  it 'runs the rake task successfully' do
    Application.load_tasks
    expect { Rake::Task['db:ensure_migrations_are_current'].invoke }.not_to raise_error
  end
end
