ExUnit.start(capture_log: true)

# Load best available test database
lambda_core = "test/fixtures/lambdacore.db"
jh_core = "test/fixtures/jhcore.db"

db_path =
  cond do
    File.exists?(lambda_core) -> lambda_core
    File.exists?(jh_core) -> jh_core
    true -> nil
  end

if db_path do
  # Wait for DB server to start
  :timer.sleep(100)

  case Alchemoo.Database.Server.load(db_path) do
    {:ok, count} -> IO.puts("Loaded #{count} objects from #{db_path}")
    {:error, reason} -> IO.puts("Failed to load #{db_path}: #{inspect(reason)}")
  end
end
