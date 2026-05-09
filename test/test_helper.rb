ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

require "factory_bot_rails"

class ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  # Captures every Placements::BroadcastLeaderboard.call(tournament:) inside the
  # block and yields the array of tournament ids broadcast to. Restores the
  # original implementation in `ensure` so failures don't leak the stub.
  def with_broadcast_spy
    calls = []
    original = Placements::BroadcastLeaderboard.method(:call)
    Placements::BroadcastLeaderboard.define_singleton_method(:call) { |tournament:| calls << tournament.id }
    begin
      yield calls
    ensure
      Placements::BroadcastLeaderboard.define_singleton_method(:call, original)
    end
    calls
  end

  # Replaces self-method `name` on `klass` with `replacement` (a callable) for
  # the duration of the block. Restores the original even if the block raises.
  def with_class_method_stub(klass, name, replacement)
    original = klass.method(name)
    klass.define_singleton_method(name, replacement)
    yield
  ensure
    klass.define_singleton_method(name, original)
  end
end

class ActionDispatch::SystemTestCase
  include FactoryBot::Syntax::Methods
end
