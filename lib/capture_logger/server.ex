# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 Austin Ziegler
# SPDX-FileCopyrightText: 2021 The Elixir Team
# SPDX-FileCopyrightText: 2012 Plataformatec

defmodule CaptureLogger.Server do
  @moduledoc false
  use GenServer

  @compile {:no_warn_undefined, Logger}
  @timeout :infinity
  @name __MODULE__
  @ets __MODULE__

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: @name)
  end

  def log_capture_on(pid, string_io, opts) do
    GenServer.call(@name, {:log_capture_on, pid, string_io, opts}, @timeout)
  end

  def log_capture_off(ref) do
    GenServer.call(@name, {:log_capture_off, ref}, @timeout)
  end

  ## Callbacks

  @impl true
  def init(:ok) do
    :ets.new(@name, [:named_table, :public, :set])

    state = %{
      log_captures: %{},
      log_status: :error
    }

    {:ok, state}
  end

  @impl true
  def handle_call(call, from, state)

  def handle_call({:log_capture_on, pid, string_io, opts}, _from, config) do
    ref = Process.monitor(pid)
    refs = Map.put(config.log_captures, ref, true)

    {level, opts} = Keyword.pop(opts, :level)
    {formatter, opts} = Keyword.pop(opts, :formatter, Application.get_env(:capture_logger, :formatter))

    {formatter_mod, formatter_config} =
      case formatter do
        {_, _} -> formatter
        nil -> Logger.default_formatter(opts)
        module when is_atom(module) -> module.new(opts)
      end

    true = :ets.insert(@ets, {ref, string_io, level || :all, formatter_mod, formatter_config})

    if map_size(refs) == 1 do
      :ok = :logger.add_handler(@name, __MODULE__, %{})

      status =
        with {:ok, config} <- :logger.get_handler_config(:default),
             :ok <- :logger.remove_handler(:default) do
          {:ok, config}
        else
          _ -> :error
        end

      {:reply, ref, %{config | log_captures: refs, log_status: status}}
    else
      {:reply, ref, %{config | log_captures: refs}}
    end
  end

  def handle_call({:log_capture_off, ref}, _from, config) do
    Process.demonitor(ref, [:flush])
    config = remove_log_capture(ref, config)
    {:reply, :ok, config}
  end

  @impl true
  def handle_info({:DOWN, ref, _, _, _}, config) do
    config = remove_log_capture(ref, config)
    {:noreply, config}
  end

  defp remove_log_capture(ref, %{log_captures: refs} = config) do
    true = :ets.delete(@ets, ref)

    case Map.pop(refs, ref, false) do
      {true, refs} ->
        maybe_revert_to_default_handler(refs, config.log_status)
        %{config | log_captures: refs}

      {false, _refs} ->
        config
    end
  end

  defp maybe_revert_to_default_handler(refs, status) when map_size(refs) == 0 do
    :logger.remove_handler(@name)

    with {:ok, %{module: module} = config} <- status do
      :logger.add_handler(:default, module, config)
    end
  end

  defp maybe_revert_to_default_handler(_refs, _config) do
    :ok
  end

  ## :logger handler callback.

  def log(event, _config) do
    {:trap_exit, trapping_exits?} = Process.info(self(), :trap_exit)

    tasks =
      @ets
      |> :ets.tab2list()
      |> Enum.filter(fn {_ref, _string_io, level, _formatter_mod, _formatter_config} ->
        :logger.compare_levels(event.level, level) in [:gt, :eq]
      end)
      |> Enum.group_by(
        fn {_ref, _string_io, _level, formatter_mod, formatter_config} ->
          {formatter_mod, formatter_config}
        end,
        fn {_ref, string_io, _level, _formatter_mod, _formatter_config} ->
          string_io
        end
      )
      |> Enum.map(fn {{formatter_mod, formatter_config}, string_ios} ->
        Task.async(fn ->
          chardata = formatter_mod.format(event, formatter_config)

          # Simply send, do not wait for reply
          for string_io <- string_ios do
            send(string_io, {:io_request, self(), make_ref(), {:put_chars, :unicode, chardata}})
          end
        end)
      end)

    Task.await_many(tasks)

    if trapping_exits? do
      for %{pid: pid} <- tasks do
        receive do
          {:EXIT, ^pid, _} -> :ok
        end
      end
    end

    :ok
  end
end
