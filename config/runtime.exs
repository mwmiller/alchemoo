import Config

if core_db = System.get_env("ALCHEMOO_CORE_DB") do
  config :alchemoo, :core_db, core_db
end
