# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 Austin Ziegler
# SPDX-FileCopyrightText: 2021 The Elixir Team
# SPDX-FileCopyrightText: 2012 Plataformatec

defmodule CaptureLogger do
  @moduledoc ~S"""
  Functionality to capture logs for testing.

  ## Examples

  ```elixir
  defmodule AssertionTest do
    use ExUnit.Case

    alias LoggerJSON.Formatters.Basic
    import CaptureLogger
    require Logger

    test "example" do
      {result, log} =
        with_log([formatter: Basic.new()], fn ->
          Logger.error("log msg")
          2 + 2
        end)

      assert result == 4
      assert Jason.decode!(log)["message"] == "log msg"
    end

    test "check multiple captures concurrently" do
      fun = fn ->
        for msg <- ["hello", "hi"] do
          log = assert capture_log(
            [formatter: Basic],
            fn -> Logger.error(msg) end
          )
          assert Jason.decode!(log)["message"] == msg
        end

        Logger.debug("testing")
      end

      assert capture_log([formatter: Basic],fun) =~ "hello"
      assert capture_log([formatter: Basic], fun) =~ "\"message\":\"testing\""
    end
  end
  ```
  """

  @doc """
  Starts the CaptureLogger server under a supervisor. This should be called with
  `ExUnit.start/1`.
  """
  def start do
    Supervisor.start_link([CaptureLogger.Server], strategy: :one_for_one, name: CaptureLogger.Supervisor)
  end

  @compile {:no_warn_undefined, Logger}

  @type capture_log_opts :: [
          {:level, Logger.level() | nil}
          | {:formatter, {module(), term()} | module() | nil}
          | {atom(), term() | nil}
        ]

  @doc """
  Captures Logger messages generated when evaluating `fun`.

  Returns the binary which is the captured output.

  This function mutes the default logger handler and captures any log messages sent to
  Logger from the calling processes. It is possible to ensure explicit log messages from
  other processes are captured by waiting for their exit or monitor signal.

  Note that when the `async` is set to `true` on `use ExUnit.Case`, messages from other
  tests might be captured. This is OK as long you consider such cases in your assertions,
  typically by using the `=~/2` operator to perform partial matches.

  To get the result of the evaluation along with the captured log, use `with_log/2`.

  ### Options

  - `:level`: Configure the level to capture with `:level`, which will set the capturing
    level for the duration of the capture. For instance, if the log level is set to
    `:error`, then any message with a lower level will be ignored. The default level is
    `nil`, which will capture all messages.

    Note this setting does not override the overall `Logger.level/0` value. Therefore, if
    `Logger.level/0` is set to a higher level than the one configured in this function, no
    message will be captured. The behaviour is undetermined if async tests change Logger
    level.

  - `:formatter`: The formatter to use for formatting log messages. May be provided either
    as `t:module/0` or as `{module, options}`. If provided as a module, it must respond to
    `new/1` and the remaining options will be provided as configuration to the formatter
    module.

    If not provided, defaults to `Logger.default_formatter/1` with any other options
    forwarded as a configuration to the default formatter.

    The default formatter may also be set with the `:formatter` configuration key for
    `:capture_logger`. When set in a compile-time configuration file (`config/test.exs`),
    it should be provided as a `{module, options}` tuple. When set in `config/runtime.exs`
    or `test/test_helper.exs`, it may be possible to call `module.new(options)`.
  """
  @spec capture_log(capture_log_opts, (-> any())) :: String.t()
  def capture_log(opts \\ [], fun) do
    {_, log} = with_log(opts, fun)
    log
  end

  @doc """
  Invokes the given `fun` and returns the result and captured log.

  It accepts the same arguments and options as `capture_log/2`.

  ## Examples

  ```elixir
  {result, log} =
    with_log(fn ->
      Logger.error("log msg")
      2 + 2
    end)

  assert result == 4
  assert log =~ "log msg"
  ```
  """
  @spec with_log(capture_log_opts, (-> result)) :: {result, log :: String.t()} when result: any()
  def with_log(opts \\ [], fun) when is_list(opts) do
    opts =
      if opts[:level] == :warn do
        IO.warn("level: :warn is deprecated, please use :warning instead")
        Keyword.put(opts, :level, :warning)
      else
        opts
      end

    {:ok, string_io} = StringIO.open("")

    try do
      ref = CaptureLogger.Server.log_capture_on(self(), string_io, opts)

      try do
        fun.()
      after
        :ok = Logger.flush()
        :ok = CaptureLogger.Server.log_capture_off(ref)
      end
    catch
      kind, reason ->
        _ = StringIO.close(string_io)
        :erlang.raise(kind, reason, __STACKTRACE__)
    else
      result ->
        {:ok, {_input, output}} = StringIO.close(string_io)
        {result, output}
    end
  end
end
