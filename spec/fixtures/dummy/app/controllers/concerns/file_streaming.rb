# frozen_string_literal: true

# A download wrapper defined in a concern, to exercise cross-module resolution.
module FileStreaming
  private

  def stream_via_concern(path)
    send_file(path)
  end
end
