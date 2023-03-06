defmodule Pooly.WorkerSupervisor do
  use DynamicSupervisor

  def start_link(%{name: name}) do
    DynamicSupervisor.start_link(__MODULE__, [], name: :"#{name}WorkerSupervisor")
  end

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 5, max_seconds: 5)
  end
end
