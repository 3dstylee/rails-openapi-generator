# frozen_string_literal: true

module Api
  class ReportsController < ApplicationController
    include FileStreaming

    # Download via a single same-controller wrapper.
    def single
      stream_report("/tmp/report.pdf")
    end

    # Download via a chain of wrappers: chained -> deliver -> stream_report.
    def chained
      deliver("/tmp/report.pdf")
    end

    # Download via a wrapper defined in an included concern.
    def via_concern
      stream_via_concern("/tmp/report.pdf")
    end

    # Cyclic wrappers that never reach send_file — resolution must not hang.
    def cyclic
      loop_a
    end

    private

    def stream_report(path)
      send_file(path)
    end

    def deliver(path)
      stream_report(path)
    end

    def loop_a
      loop_b
    end

    def loop_b
      loop_a
    end
  end
end
