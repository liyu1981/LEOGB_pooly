defmodule Pooly do
  use Application

  def start(_type, _args) do
    pool_configs = [
      %{
        name: "pool1",
        ma: {SampleWorker, []},
        size: 5
      },
      %{
        name: "pool2",
        ma: {SampleWorker, []},
        size: 4
      },
      %{
        name: "pool3",
        ma: {SampleWorker, []},
        size: 3
      }
    ]

    start_pools(pool_configs)
  end

  def start_pools(pool_configs) do
    Pooly.Supervisor.start_link(pool_configs)
  end

  def checkout(pool_name) do
    Pooly.Server.checkout(pool_name)
  end

  def checkin(pool_name, worker_pid) do
    Pooly.Server.checkin(pool_name, worker_pid)
  end

  def status(pool_name) do
    Pooly.Server.status(pool_name)
  end
end
