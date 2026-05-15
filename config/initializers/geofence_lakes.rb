# Parse the 17 lake polygon JSON files (~2.6 MB) at boot rather than on the
# first POST /catches after a Puma restart. Catches are time-sensitive — the
# user just landed a fish — so we don't want them paying the load cost.
#
# Skipped in test envs where each test reloads the registry on demand.
Rails.application.config.after_initialize do
  next if Rails.env.test?
  Geofence::Lakes.load! if defined?(Geofence::Lakes)
end
