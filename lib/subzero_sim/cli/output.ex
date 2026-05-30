defmodule SubzeroSim.CLI.Output do
  @moduledoc """
  Shared output helpers for CLI commands.
  """

  @doc """
  Prints a success message in green.
  """
  def success(msg), do: IO.puts(colorize("[PASS] #{msg}", :green))

  @doc """
  Prints an error message in red to stderr.
  """
  def error(msg), do: IO.puts(:stderr, colorize("[ERROR] #{msg}", :red))

  @doc """
  Prints an info message in cyan.
  """
  def info(msg), do: IO.puts(colorize(msg, :cyan))

  @doc """
  Prints a warning message in yellow.
  """
  def warning(msg), do: IO.puts(colorize("[WARN] #{msg}", :yellow))

  @doc """
  Prints dimmed text.
  """
  def dim(msg), do: IO.puts(colorize(msg, :dim))

  @doc """
  Prints text without newline.
  """
  def puts(msg), do: IO.puts(msg)

  @doc """
  Prints a newline.
  """
  def newline, do: IO.puts("")

  @doc """
  Prints a header with underline.
  """
  def header(text) do
    IO.puts("")
    IO.puts(colorize(text, :bold))
    IO.puts(String.duplicate("─", String.length(text)))
  end

  @doc """
  Formats a key-value pair.
  """
  def kv(key, value) do
    "#{colorize(key <> ":", :dim)} #{value}"
  end

  @doc """
  Prints a formatted table.
  """
  def table(headers, rows) do
    # Calculate column widths
    all_rows = [headers | rows]

    widths =
      Enum.reduce(all_rows, List.duplicate(0, length(headers)), fn row, widths ->
        row
        |> Enum.zip(widths)
        |> Enum.map(fn {cell, width} -> max(String.length(to_string(cell)), width) end)
      end)

    # Print header
    header_row =
      headers
      |> Enum.zip(widths)
      |> Enum.map(fn {cell, width} -> String.pad_trailing(to_string(cell), width) end)
      |> Enum.join("  ")

    IO.puts(colorize(header_row, :bold))

    # Print separator
    separator =
      widths
      |> Enum.map(&String.duplicate("─", &1))
      |> Enum.join("──")

    IO.puts(colorize(separator, :dim))

    # Print rows
    Enum.each(rows, fn row ->
      formatted =
        row
        |> Enum.zip(widths)
        |> Enum.map(fn {cell, width} -> String.pad_trailing(to_string(cell), width) end)
        |> Enum.join("  ")

      IO.puts(formatted)
    end)
  end

  @doc """
  Colorizes text with ANSI codes.
  """
  def colorize(text, color) do
    if IO.ANSI.enabled?() do
      IO.ANSI.format([color_code(color), text, :reset])
      |> IO.iodata_to_binary()
    else
      to_string(text)
    end
  end

  defp color_code(:green), do: :green
  defp color_code(:red), do: :red
  defp color_code(:cyan), do: :cyan
  defp color_code(:yellow), do: :yellow
  defp color_code(:blue), do: :blue
  defp color_code(:magenta), do: :magenta
  defp color_code(:white), do: :white
  defp color_code(:bold), do: :bright
  defp color_code(:dim), do: :faint
  defp color_code(_), do: :reset
end
