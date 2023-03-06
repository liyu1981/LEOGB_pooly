defmodule Pooly.PoolSupervisor do
  use Supervisor

  def start_link(%{name: name} = pool_config) do
    Supervisor.start_link(__MODULE__, pool_config, name: :"#{name}Supervisor")
  end

  @impl true
  def init(pool_config) do
    children = [
      {Pooly.PoolServer, pool_config},
      {Pooly.WorkerSupervisor, pool_config}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
