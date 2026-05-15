# Parse the 17 lake polygon JSON files (~2.6 MB) at boot rather than on the
# first POST /catches after a Puma restart. Catches are time-sensitive — the
# user just landed a fish — so we don't want them paying the load cost.
#
# Skipped in test envs where the test loads its own fixtures and the Lakes
# registry is exercised on demand. Also skipped during asset precompilation
# and migrations so they don't pay the cost they don't need.
Rails.application.config.after_initialize do
  next if Rails.env.test?
  next if defined?(Rails::Command::AssetsCommand)
  Geofence::Lakes.load! if defined?(Geofence::Lakes)
end
