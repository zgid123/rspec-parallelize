# frozen_string_literal: true

require 'io/console'

module RSpec
  module Parallelize
    # A live status line pinned to the bottom row of the terminal:
    #
    #   rspec-parallelize: 1234/6288 examples · 2 failures · 12/12 workers busy · 41s
    #
    # The rows above it become a scroll region, so formatter output (dots,
    # failures) scrolls as usual without overwriting the line. Only shown on
    # an interactive terminal; never in CI, when piped, or with
    # RSPEC_PARALLELIZE_PROGRESS=0.
    class ProgressLine
      MIN_ROWS = 3

      def initialize(output)
        @output = output
        @active = false
      end

      def enabled?
        @output.respond_to?(:tty?) && @output.tty? &&
          !ENV.key?('CI') && ENV['RSPEC_PARALLELIZE_PROGRESS'] != '0' &&
          rows >= MIN_ROWS
      end

      def start
        return unless enabled?

        @rows = rows
        # Make room for the status line, then confine scrolling to the rows above it.
        write("\n\e[1A")
        reserve_bottom_row
        @active = true
      end

      def update(text)
        return unless @active

        if rows != @rows # terminal was resized
          @rows = rows
          reserve_bottom_row
        end

        write("\e7\e[#{@rows};1H\e[2K#{text[0, columns - 1]}\e8")
      end

      def stop
        return unless @active

        @active = false
        write("\e7\e[#{@rows};1H\e[2K\e[r\e8")
      end

      private

      # DECSTBM moves the cursor home, hence the save/restore around it.
      def reserve_bottom_row
        write("\e7\e[1;#{@rows - 1}r\e8")
      end

      def rows
        @output.winsize[0]
      rescue StandardError
        0
      end

      def columns
        @output.winsize[1]
      rescue StandardError
        80
      end

      def write(sequence)
        @output.write(sequence)
        @output.flush
      end
    end
  end
end
