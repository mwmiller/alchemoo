import Config

config :logger, level: :warning

config :alchemoo, :network,
  telnet: %{
    enabled: true,
    port: fn ->
      seed =
        case Code.ensure_loaded?(ExUnit) && ExUnit.configuration()[:seed] do
          nil -> :erlang.phash2(make_ref(), 10_000)
          0 -> :erlang.phash2(make_ref(), 10_000)
          val -> val
        end

      10_007 + rem(seed, 9973)
    end
  }
