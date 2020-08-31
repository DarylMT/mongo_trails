require 'test_helper'

class WriteVersionWorker
  include Sidekiq::Worker

  def perform(obj)
    PaperTrail::Version.new(obj).save
  end
end

class UnknownWorker
end

class SidekiqIntegrationTest < Minitest::Test
  def setup
    Mongoid.purge!
    WriteVersionWorker.clear
    User.delete_all
    PaperTrail.request.whodunnit = 'Andy Stewart'
  end

  def seed_records
    @user = User.create(name: 'Bob')
    [*1..20].each do |i|
      @user.update!(name: "Bob #{i}")
    end
  end

  def test_sidekiq_integration_enabled
    PaperTrail.config.enable_sidekiq = true
    PaperTrail.config.sidekiq_worker = WriteVersionWorker
    seed_records
    assert_equal 21, WriteVersionWorker.jobs.size

    Sidekiq::Worker.drain_all

    assert_equal 21, @user.versions.count
  end

  def test_sidekiq_integration_disabled
    PaperTrail.config.enable_sidekiq = false
    PaperTrail.config.sidekiq_worker = WriteVersionWorker
    seed_records
    assert_equal 0, WriteVersionWorker.jobs.size

    assert_equal 21, @user.versions.count
  end

  # Fallback from poorly defined worker to a built-in
  def test_sidekiq_poor_definition
    PaperTrail.config.enable_sidekiq = true
    PaperTrail.config.sidekiq_worker = UnknownWorker
    PaperTrail.config.sidekiq_options = { queue: :another }
    seed_records

    assert_equal 21, PaperTrail::WriteVersionWorker.jobs.size
    assert_equal 'another', PaperTrail::WriteVersionWorker.jobs.last['queue']

    Sidekiq::Worker.drain_all

    assert_equal 21, @user.versions.count
  end
end
