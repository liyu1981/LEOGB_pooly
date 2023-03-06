defmodule Pooly.PoolServer do
  use GenServer

  defmodule State do
    defstruct name: nil,
              size: nil,
              ma: nil,
              monitors: nil,
              workers: nil
  end

  def start_link(%{name: name} = pool_config) do
    GenServer.start_link(__MODULE__, pool_config, name: :"#{name}Server")
  end

  @impl true
  def init(%{name: name, ma: ma, size: size}) do
    Process.flag(:trap_exit, true)
    monitors = :ets.new(:monitors, [:private])
    state = %State{name: name, monitors: monitors, ma: ma, size: size}
    send(self(), :start_worker_supervisor)
    {:ok, state}
  end

  @impl true
  def handle_info(:start_worker_supervisor, state = %{name: name, ma: {m, a}, size: size}) do
    worker_sup_name = :"#{name}WorkerSupervisor"
    workers = prepopulate(size, worker_sup_name, {m, a})
    {:noreply, %{state | workers: workers}}
  end

  def handle_info({:DOWN, ref, _, _, _}, state = %{monitors: monitors, workers: workers}) do
    case :ets.match(monitors, {:"$1", ref}) do
      [[pid]] ->
        true = :ets.delete(monitors, pid)
        new_state = %{state | workers: [pid | workers]}
        {:noreply, new_state}

      [[]] ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:EXIT, pid, _reason},
        state = %{ma: ma, monitors: monitors, workers: workers, worker_sup: worker_sup}
      ) do
    case :ets.lookup(monitors, pid) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, pid)
        new_state = %{state | workers: [new_worker(worker_sup, ma) | workers]}
        {:noreply, new_state}

      [{}] ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:checkout, {from_pid, _}, %{workers: workers, monitors: monitors} = state) do
    case workers do
      [worker | rest] ->
        ref = Process.monitor(from_pid)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{state | workers: rest}}

      [] ->
        {:reply, :noproc, state}
    end
  end

  def handle_call({:checkin, worker}, _from, %{workers: workers, monitors: monitors} = state) do
    case :ets.lookup(monitors, worker) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, pid)
        {:reply, :ok, %{state | workers: [pid | workers]}}

      [] ->
        {:reply, :ok, state}
    end
  end

  def handle_call(:status, _from, %{name: name, workers: workers, monitors: monitors} = state) do
    {:reply,
     {:name, name, :pid, self(), :free, length(workers), :inuse, :ets.info(monitors, :size)},
     state}
  end

  defp prepopulate(size, sup, ma) do
    prepopulate(size, sup, ma, [])
  end

  defp prepopulate(size, _sup, _ma, workers) when size < 1 do
    workers
  end

  defp prepopulate(size, sup, ma, workers) do
    prepopulate(size - 1, sup, ma, [new_worker(sup, ma) | workers])
  end

  defp new_worker(sup, ma) do
    {:ok, worker} = DynamicSupervisor.start_child(sup, ma)
    Process.link(worker)
    worker
  end
end
