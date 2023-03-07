defmodule Pooly.PoolServer do
  use GenServer

  defmodule State do
    defstruct name: nil,
              size: nil,
              ma: nil,
              monitors: nil,
              workers: nil,
              overflow: nil,
              max_overflow: nil,
              waiting: nil
  end

  def start_link(%{name: name} = pool_config) do
    GenServer.start_link(__MODULE__, pool_config, name: :"#{name}Server")
  end

  @impl true
  def init(%{name: name, ma: ma, size: size, max_overflow: max_overflow}) do
    Process.flag(:trap_exit, true)
    monitors = :ets.new(:monitors, [:private])
    waiting = :queue.new()

    state = %State{
      name: name,
      monitors: monitors,
      ma: ma,
      size: size,
      overflow: 0,
      max_overflow: max_overflow,
      waiting: waiting
    }

    send(self(), :start_worker_supervisor)
    {:ok, state}
  end

  @impl true
  def handle_info(:start_worker_supervisor, state = %{name: name, ma: {m, a}, size: size}) do
    workers = prepopulate(size, worker_sup_name(name), {m, a})
    {:noreply, %{state | workers: workers}}
  end

  def handle_info(
        {:DOWN, ref, _, _, _},
        state = %{monitors: monitors, workers: workers, overflow: overflow, waiting: waiting}
      ) do
    case :queue.any(fn {_, ref_waiting} -> ref_waiting == ref end, waiting) do
      # if it is the process in waiting queue down
      true ->
        new_waiting = :queue.filter(fn {_, ref_waiting} -> ref_waiting != ref end, waiting)
        {:noreply, %{state | waiting: new_waiting}}

      # otherwise must be some process checked out a worker
      false ->
        true = Process.demonitor(ref)

        case :ets.match(monitors, {:"$1", ref}) do
          [[pid]] ->
            true = :ets.delete(monitors, pid)

            case :queue.out(waiting) do
              {{:value, {from_waiting, ref_waiting}}, left_waiting} ->
                true = :ets.insert(pid, {pid, ref_waiting})
                GenServer.reply(from_waiting, pid)
                {:noreply, %{state | waiting: left_waiting}}

              {:empty, _} when overflow > 0 ->
                {:noreply, %{state | overflow: overflow - 1}}

              {:empty, _} ->
                {:noreply, %{state | workers: [pid | workers]}}
            end

          [[]] ->
            {:noreply, state}
        end
    end
  end

  def handle_info(
        {:EXIT, pid, _reason},
        state = %{
          name: name,
          ma: ma,
          monitors: monitors,
          workers: workers,
          overflow: overflow,
          waiting: waiting
        }
      ) do
    case :ets.lookup(monitors, pid) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, pid)

        case :queue.out(waiting) do
          {{:value, {from_waiting, ref_waiting}}, left_waiting} ->
            new_worker = new_worker(worker_sup_name(name), ma)
            true = :ets.insert(monitors, {pid, ref_waiting})
            GenServer.reply(from_waiting, new_worker)
            {:noreply, %{state | workers: [new_worker | workers], waiting: left_waiting}}

          {:empty, _} when overflow > 0 ->
            {:noreply, %{state | overflow: overflow - 1}}

          {:empty, _} ->
            {:noreply, state}
        end

      [] ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(
        {:checkout, block},
        {from_pid, _} = from,
        %{
          name: name,
          ma: ma,
          workers: workers,
          monitors: monitors,
          overflow: overflow,
          max_overflow: max_overflow,
          waiting: waiting
        } = state
      ) do
    case workers do
      [worker | rest] ->
        ref = Process.monitor(from_pid)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{state | workers: rest}}

      [] when max_overflow > 0 and overflow < max_overflow ->
        ref = Process.monitor(from_pid)
        worker = new_worker(worker_sup_name(name), ma)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{state | overflow: overflow + 1}}

      [] when block == true ->
        ref = Process.monitor(from_pid)
        new_waiting = :queue.in({from, ref}, waiting)
        {:noreply, %{state | waiting: new_waiting}, :infinity}

      [] ->
        {:reply, :full, state}
    end
  end

  def handle_call(
        {:checkin, worker},
        _from,
        %{name: name, workers: workers, monitors: monitors, overflow: overflow, waiting: waiting} =
          state
      ) do
    case :ets.lookup(monitors, worker) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, pid)

        case :queue.out(waiting) do
          {{:value, {from_waiting, ref_waiting}}, left_waiting} ->
            true = :ets.insert(monitors, {pid, ref_waiting})
            GenServer.reply(from_waiting, pid)
            {:reply, :ok, %{state | waiting: left_waiting}}

          {:empty, _} when overflow > 0 ->
            :ok = terminate_worker(worker_sup_name(name), worker)
            {:reply, :ok, %{state | overflow: overflow - 1}}

          {:empty, _} ->
            {:reply, :ok, %{state | workers: [pid | workers]}}
        end

      [] ->
        {:reply, :ok, state}
    end
  end

  def handle_call(
        :status,
        _from,
        %{
          name: name,
          workers: workers,
          monitors: monitors,
          overflow: overflow,
          max_overflow: max_overflow,
          waiting: waiting
        } = state
      ) do
    {:reply,
     {:name, name, :pid, self(), :free, length(workers), :inuse, :ets.info(monitors, :size),
      :overflow, "#{overflow}/#{max_overflow}", :waiting, :queue.len(waiting)}, state}
  end

  defp worker_sup_name(name) do
    :"#{name}WorkerSupervisor"
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

  defp terminate_worker(sup, worker) do
    DynamicSupervisor.terminate_child(sup, worker)
  end
end
