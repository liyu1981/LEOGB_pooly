defmodule Pooly.Server do
  use GenServer

  def start_link(pool_configs) when is_list(pool_configs) do
    GenServer.start_link(__MODULE__, pool_configs, name: __MODULE__)
  end

  def checkout(pool_name) do
    GenServer.call(:"#{pool_name}Server", :checkout)
  end

  def checkin(pool_name, worker_pid) do
    GenServer.call(:"#{pool_name}Server", {:checkin, worker_pid})
  end

  def status(pool_name) do
    GenServer.call(:"#{pool_name}Server", :status)
  end

  @impl true
  def init(pool_configs) do
    pool_configs
    |> Enum.each(fn pool_config ->
      send(self(), {:start_pool, pool_config})
    end)

    {:ok, pool_configs}
  end

  @impl true
  def handle_info({:start_pool, pool_config}, state) do
    {:ok, _} = Supervisor.start_child(Pooly.PoolsSupervisor, pool_supervisor_spec(pool_config))
    {:noreply, state}
  end

  defp pool_supervisor_spec(%{name: name} = pool_config) do
    Supervisor.child_spec({Pooly.PoolSupervisor, pool_config}, id: "#{name}PoolSupervisor")
  end
end
