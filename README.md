# CaptureLogger

- code :: <https://github.com/halostatue/capture_logger>
- issues :: <https://github.com/halostatue/capture_logger/issues>

CaptureLogger is variant of ExUnit.CaptureLog that allows specification of a
variant formatter to be specified.

## Usage

CaptureLogger is intended to be used in the same way as [ExUnit.CaptureLog][cl].
Because it uses a different capture server than ExUnit.CaptureLog, it is
necessary to start the CaptureLogger server in `test/test_helper.exs`:

```elixir
ExUnit.start()
CaptureLogger.start()
```

Once done, `CaptureLogger` can be imported the same as `ExUnit.CaptureLog` and
used with a custom formatter:

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

## Installation

CaptureLogger can be installed by adding `capture_logger` to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:capture_logger, "~> 1.0"}
  ]
end
```

Documentation is found on [HexDocs][docs].

## Semantic Versioning

CaptureLogger follows [Semantic Versioning 2.0][semver].

[12f]: https://12factor.net/
[cl]: https://hexdocs.com/ex_unit/capture_log.html
[docs]: https://hexdocs.pm/ex_unit/ExUnit.CaptureLog.html
[semver]: https://semver.org/
