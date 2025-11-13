# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 Austin Ziegler
# SPDX-FileCopyrightText: 2021 The Elixir Team
# SPDX-FileCopyrightText: 2012 Plataformatec

# credo:disable-for-this-file Credo.Check.Warning.MissedMetadataKeyInLoggerConfig
defmodule CaptureLoggerTest do
  use ExUnit.Case

  import CaptureLogger

  alias LoggerJSON.Formatters.Basic

  require Logger

  @formatter Basic.new()

  test "no output" do
    assert capture_log(fn -> nil end) == ""
  end

  test "assert inside" do
    group_leader = Process.group_leader()

    try do
      capture_log(fn ->
        assert false
      end)
    rescue
      error in [ExUnit.AssertionError] ->
        assert error.message == "Expected truthy, got false"
    end

    # Ensure no leakage on failures
    assert group_leader == Process.group_leader()
    refute_received {:gen_event_EXIT, _, _}
  end

  test "level aware" do
    assert capture_log([level: :warning], fn ->
             Logger.info("here")
           end) == ""
  end

  test "level aware with formatter" do
    assert capture_log([formatter: @formatter, level: :warning], fn ->
             Logger.info("here")
           end) == ""
  end

  @tag timeout: 2000
  test "capture removal on exit" do
    {_pid, ref} =
      spawn_monitor(fn ->
        capture_log(fn ->
          spawn_link(Kernel, :exit, [:shutdown])
          Process.sleep(:infinity)
        end)
      end)

    assert_receive {:DOWN, ^ref, _, _, :shutdown}
    wait_capture_removal()
  end

  test "log tracking" do
    logged =
      capture_log(fn ->
        Logger.info("one")

        logged = capture_log(fn -> Logger.error("one") end)
        send(test = self(), {:nested, logged})

        Logger.warning("two")

        spawn(fn ->
          Logger.debug("three")
          send(test, :done)
        end)

        receive do: (:done -> :ok)
      end)

    assert logged
    assert logged =~ "[info] one"
    assert logged =~ "[warning] two"
    assert logged =~ "[debug] three"
    assert logged =~ "[error] one"

    receive do
      {:nested, logged} ->
        assert logged =~ "[error] one"
        refute logged =~ "[warning] two"
    end
  end

  test "log tracking with formatter" do
    logged =
      capture_log([formatter: @formatter], fn ->
        Logger.info("one")

        logged = capture_log([formatter: @formatter], fn -> Logger.error("one") end)
        send(test = self(), {:nested, logged})

        Logger.warning("two")

        spawn(fn ->
          Logger.debug("three")
          send(test, :done)
        end)

        receive do: (:done -> :ok)
      end)

    assert logged

    lines = decode_lines(logged)

    assert Enum.find(lines, &match?(%{"severity" => "info", "message" => "one"}, &1))
    assert Enum.find(lines, &match?(%{"severity" => "warning", "message" => "two"}, &1))
    assert Enum.find(lines, &match?(%{"severity" => "debug", "message" => "three"}, &1))
    assert Enum.find(lines, &match?(%{"severity" => "error", "message" => "one"}, &1))

    receive do
      {:nested, logged} ->
        lines = decode_lines(logged)
        assert Enum.find(lines, &match?(%{"severity" => "error", "message" => "one"}, &1))
        refute Enum.find(lines, &match?(%{"severity" => "warning", "message" => "two"}, &1))
    end
  end

  test "log tracking with formatter module" do
    logged =
      capture_log([formatter: Basic], fn ->
        Logger.info("one")

        logged = capture_log([formatter: Basic], fn -> Logger.error("one") end)
        send(test = self(), {:nested, logged})

        Logger.warning("two")

        spawn(fn ->
          Logger.debug("three")
          send(test, :done)
        end)

        receive do: (:done -> :ok)
      end)

    assert logged

    lines = decode_lines(logged)

    assert Enum.find(lines, &match?(%{"severity" => "info", "message" => "one"}, &1))
    assert Enum.find(lines, &match?(%{"severity" => "warning", "message" => "two"}, &1))
    assert Enum.find(lines, &match?(%{"severity" => "debug", "message" => "three"}, &1))
    assert Enum.find(lines, &match?(%{"severity" => "error", "message" => "one"}, &1))

    receive do
      {:nested, logged} ->
        lines = decode_lines(logged)
        assert Enum.find(lines, &match?(%{"severity" => "error", "message" => "one"}, &1))
        refute Enum.find(lines, &match?(%{"severity" => "warning", "message" => "two"}, &1))
    end
  end

  test "deprecated log level" do
    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      output =
        capture_log([level: :warn], fn ->
          Logger.log(:warn, "ABC")
          Logger.log(:warning, "DEF")
        end)

      assert output =~ "ABC"
      assert output =~ "DEF"
    end)
  end

  test "exits don't leak" do
    Process.flag(:trap_exit, true)

    capture_log(fn ->
      Logger.error("oh no!")
    end)

    refute_receive {:EXIT, _, _}, 100
  end

  describe "with_log/2" do
    test "returns the result and the log" do
      {result, log} =
        with_log(fn ->
          Logger.error("calculating...")
          2 + 2
        end)

      assert result == 4
      assert log =~ "calculating..."
    end

    test "respects the :format, :metadata, and :colors options" do
      options = [format: "$metadata| $message", metadata: [:id], colors: [enabled: false]]

      assert {4, log} =
               with_log(options, fn ->
                 Logger.info("hello", id: 123)
                 2 + 2
               end)

      assert log == "id=123 | hello"
    end

    test "respects the :metadata option with a formatter" do
      options = [formatter: Basic, metadata: [:id]]

      assert {4, log} =
               with_log(options, fn ->
                 Logger.info("hello", id: 123)
                 2 + 2
               end)

      assert %{"metadata" => %{"id" => 123}} = Jason.decode!(log)
    end

    @tag capture_log: true
    test "respect options with capture_log: true" do
      options = [format: "$metadata| $message", metadata: [:id], colors: [enabled: false]]

      assert {4, log} =
               with_log(options, fn ->
                 Logger.info("hello", id: 123)
                 2 + 2
               end)

      assert log == "id=123 | hello"
    end
  end

  @tag capture_log: true
  test "respects the :metadata option with a formatter and capture_log: true" do
    options = [formatter: Basic, metadata: [:id]]

    assert {4, log} =
             with_log(options, fn ->
               Logger.info("hello", id: 123)
               2 + 2
             end)

    assert %{"metadata" => %{"id" => 123}} = Jason.decode!(log)
  end

  test "handles complex :metadata with a formatter" do
    options = [formatter: Basic, metadata: [:details]]

    assert {4, log} =
             with_log(options, fn ->
               Logger.info("hello",
                 details: %{
                   customer_id: 456,
                   list: ["a", "b", "c"],
                   tuple: {1, 2}
                 }
               )

               2 + 2
             end)

    assert %{
             "metadata" => %{
               "details" => %{
                 "customer_id" => 456,
                 "list" => ["a", "b", "c"],
                 "tuple" => [1, 2]
               }
             }
           } = Jason.decode!(log)
  end

  describe "tests from CaptureLogger docs" do
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
          log =
            assert capture_log(
                     [formatter: Basic],
                     fn -> Logger.error(msg) end
                   )

          assert Jason.decode!(log)["message"] == msg
        end

        Logger.debug("testing")
      end

      assert capture_log([formatter: Basic], fun) =~ "hello"
      assert capture_log([formatter: Basic], fun) =~ ~s("message":"testing")
    end
  end

  defp decode_lines(lines) do
    lines
    |> String.trim()
    |> String.split("\n")
    |> Enum.map(fn line ->
      assert {:ok, decoded} = Jason.decode(line)
      decoded
    end)
  end

  defp wait_capture_removal do
    if CaptureLogger.Server in Enum.map(:logger.get_handler_config(), & &1.id) do
      Process.sleep(20)
      wait_capture_removal()
    else
      :ok
    end
  end
end
