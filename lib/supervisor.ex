defmodule Pooly.Supervisor do
  use Supervisor

  def start_link(pool_configs) do
    Supervisor.start_link(__MODULE__, pool_configs)
  end

  @impl true
  def init(pool_configs) do
    children = [
      %{
        id: :"Pooly.PoolsSupervisor",
        start: {Pooly.PoolsSupervisor, :start_link, []},
        restart: :permanent
      },
      %{
        id: :"Pooly.Server",
        start: {Pooly.Server, :start_link, [pool_configs]},
        restart: :permanent
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
