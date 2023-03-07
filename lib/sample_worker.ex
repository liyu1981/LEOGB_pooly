defmodule SampleWorker do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, [])
  end

  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  def work_for(pid, duration) do
    GenServer.cast(pid, {:work_for, duration})
  end

  @impl true
  def init(_init_arg) do
    {:ok, %{called: 0}}
  end

  @impl true
  def handle_call(:hello, _from, %{called: called} = state) do
    {:reply, :world, %{state | called: called + 1}}
  end

  @impl true
  def handle_call(:status, _from, %{called: called} = state) do
    {:reply, "called: #{called}", state}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_cast({:work_for, duration}, state) do
    :timer.sleep(duration)
    {:stop, :normal, state}
  end
end
