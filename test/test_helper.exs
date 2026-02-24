ExUnit.start(capture_log: true)

# Load minimal test database
path = "test/fixtures/minimal.db"
if File.exists?(path) do
  # Wait for DB server to start
  :timer.sleep(100)
  Alchemoo.Database.Server.load(path)
end
