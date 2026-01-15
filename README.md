# CaptureLogger

[![Hex.pm][shield-hex]][hexpm] [![Hex Docs][shield-docs]][docs]
[![Apache 2.0][shield-licence]][licence] ![Coveralls][shield-coveralls]

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

[cl]: https://hexdocs.pm/ex_unit/ExUnit.CaptureLog.html
[docs]: https://hexdocs.pm/capture_logger
[hexpm]: https://hex.pm/packages/capture_logger
[licence]: https://github.com/halostatue/capture_logger/blob/main/LICENCE.md
[semver]: https://semver.org/
[shield-coveralls]: https://img.shields.io/coverallsCoverage/github/halostatue/capture_logger?style=for-the-badge
[shield-docs]: https://img.shields.io/badge/hex-docs-lightgreen.svg?style=for-the-badge "Hex Docs"
[shield-hex]: https://img.shields.io/hexpm/v/capture_logger?style=for-the-badge "Hex Version"
[shield-licence]: https://img.shields.io/hexpm/l/capture_logger?style=for-the-badge&label=licence "Apache 2.0"
